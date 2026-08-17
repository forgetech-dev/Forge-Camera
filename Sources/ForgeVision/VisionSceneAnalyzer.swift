import ForgeCore
import ForgeFrame
import Foundation
import Vision

/// On-device perception: one camera frame in, portable scene state out.
///
/// Runs entirely locally. Nothing here reaches a network, and no image leaves the
/// device — the AI director sees structured state, not video.
///
/// All Vision geometry is converted at this boundary. Vision reports a bottom-left
/// origin with y increasing upward; the domain uses a top-left origin with y
/// increasing downward. Every coordinate crossing this type is flipped exactly once,
/// here, so nothing downstream has to know Vision's convention exists.
public struct VisionSceneAnalyzer: SceneAnalyzer {
    public typealias FrameContent = PixelBufferFrame

    public struct Options: Sendable {
        /// Minimum detection confidence before a subject is reported at all.
        public var minimumSubjectConfidence: Float
        /// Minimum per-joint confidence before a joint is included in a pose.
        public var minimumJointConfidence: Float
        /// Whether to run the more expensive body-pose request.
        public var detectsBodyPose: Bool

        public init(
            minimumSubjectConfidence: Float = 0.3,
            minimumJointConfidence: Float = 0.2,
            detectsBodyPose: Bool = true
        ) {
            self.minimumSubjectConfidence = minimumSubjectConfidence
            self.minimumJointConfidence = minimumJointConfidence
            self.detectsBodyPose = detectsBodyPose
        }

        public static let `default` = Options()
    }

    private let options: Options
    private let tracker: SubjectTracker

    public init(options: Options = .default) {
        self.options = options
        tracker = SubjectTracker()
    }

    public func analyze(
        _ frame: SceneFrame<PixelBufferFrame>,
        previous: SceneState?
    ) async -> SceneState {
        let observations = await detect(in: frame.content)

        // Identity is assigned here rather than by Vision: guidance that jumps
        // between people is worse than no guidance, so a detection has to be matched
        // to whoever it most plausibly continues.
        let subjects = await tracker.track(
            observations,
            previous: previous?.subjects ?? [],
            minimumConfidence: options.minimumSubjectConfidence
        )

        return SceneState(
            timestamp: frame.timestamp,
            frame: frame.geometry,
            subjects: subjects,
            horizon: nil,
            lighting: nil,
            motion: nil,
            camera: nil
        )
    }

    // MARK: - Vision

    /// One handler, every request. Vision shares work across requests in a single
    /// pass, so batching costs less than issuing them separately.
    private func detect(in content: PixelBufferFrame) async -> [SubjectObservation] {
        let handler = ImageRequestHandler(content.pixelBuffer)
        // The buffer is already orientation-corrected at the capture boundary, so no
        // further orientation is declared here.

        var humanRequest = DetectHumanRectanglesRequest()
        // Whole-body boxes: subject scale and placement guidance both depend on the
        // full figure, not the upper body.
        humanRequest.upperBodyOnly = false

        do {
            if options.detectsBodyPose {
                let poseRequest = DetectHumanBodyPoseRequest()
                let (humans, poses) = try await handler.perform(humanRequest, poseRequest)
                return merge(humans: humans, poses: poses)
            }
            let humans = try await handler.perform(humanRequest)
            return merge(humans: humans, poses: [])
        } catch {
            // A frame that cannot be analyzed yields an empty scene rather than
            // stopping the pipeline. The next frame is a fraction of a second away.
            return []
        }
    }

    /// Vision does not correlate the outputs of two requests, so the pose belonging to
    /// each detected person has to be worked out here.
    ///
    /// A body-pose observation carries no bounding box, so the match is made on the
    /// centroid of its confident joints: the pose whose body sits inside a person's
    /// box is that person's pose. Each pose is claimed at most once, so two people
    /// standing close together cannot both be given the same skeleton.
    private func merge(
        humans: [HumanObservation],
        poses: [HumanBodyPoseObservation]
    ) -> [SubjectObservation] {
        var availablePoses = poses.map { (pose: $0, centroid: centroid(of: $0)) }

        return humans.map { human in
            let bounds = human.boundingBox.forgeRect

            let matchIndex = availablePoses.firstIndex { candidate in
                guard let centroid = candidate.centroid else { return false }
                return bounds.contains(centroid)
            }

            var pose: BodyPose?
            if let matchIndex {
                pose = bodyPose(from: availablePoses[matchIndex].pose)
                availablePoses.remove(at: matchIndex)
            }

            return SubjectObservation(
                bounds: bounds,
                confidence: Double(human.confidence),
                pose: pose
            )
        }
    }

    /// The mean position of a pose's confident joints, in Forge space.
    private func centroid(of observation: HumanBodyPoseObservation) -> ForgeCore.NormalizedPoint? {
        let points = observation.allJoints().values
            .filter { Double($0.confidence) >= Double(options.minimumJointConfidence) }
            .map(\.location.forgePoint)
        guard !points.isEmpty else { return nil }

        let count = Double(points.count)
        return ForgeCore.NormalizedPoint(
            x: points.reduce(0) { $0 + $1.x } / count,
            y: points.reduce(0) { $0 + $1.y } / count
        )
    }

    private func bodyPose(from observation: HumanBodyPoseObservation) -> BodyPose {
        // One call rather than fourteen lookups: Vision returns the whole set already.
        let visionJoints = observation.allJoints()

        let joints = Self.jointMapping.compactMap { name, visionName -> BodyJoint? in
            guard let joint = visionJoints[visionName] else { return nil }
            let confidence = Double(joint.confidence)
            // A low-confidence joint is dropped rather than smoothed: pose guidance
            // built on a hallucinated skeleton is worse than pose guidance withheld.
            guard confidence >= Double(options.minimumJointConfidence) else { return nil }
            return BodyJoint(
                name: name,
                position: joint.location.forgePoint,
                confidence: confidence
            )
        }

        return BodyPose(joints: joints)
    }

    /// The domain's joints, and where Vision keeps each one.
    private static let jointMapping: [(BodyJoint.Name, HumanBodyPoseObservation.PoseJointName)] = [
        (.nose, .nose),
        (.neck, .neck),
        (.leftShoulder, .leftShoulder),
        (.rightShoulder, .rightShoulder),
        (.leftElbow, .leftElbow),
        (.rightElbow, .rightElbow),
        (.leftWrist, .leftWrist),
        (.rightWrist, .rightWrist),
        (.leftHip, .leftHip),
        (.rightHip, .rightHip),
        (.leftKnee, .leftKnee),
        (.rightKnee, .rightKnee),
        (.leftAnkle, .leftAnkle),
        (.rightAnkle, .rightAnkle),
    ]
}

/// One frame's detection of a person, before identity is assigned.
struct SubjectObservation: Sendable {
    let bounds: ForgeCore.NormalizedRect
    let confidence: Double
    let pose: BodyPose?
}
