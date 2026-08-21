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
public actor VisionSceneAnalyzer: SceneAnalyzer {
    public typealias FrameContent = PixelBufferFrame

    public struct Options: Sendable {
        /// Minimum detection confidence before a subject is reported at all.
        public var minimumSubjectConfidence: Float
        /// Minimum per-joint confidence before a joint is included in a pose.
        public var minimumJointConfidence: Float
        /// Whether to run the more expensive body-pose request.
        public var detectsBodyPose: Bool
        /// Minimum confidence for retaining the AI-selected region tracker.
        public var minimumSelectionTrackingConfidence: Float

        public init(
            minimumSubjectConfidence: Float = 0.3,
            minimumJointConfidence: Float = 0.2,
            detectsBodyPose: Bool = true,
            minimumSelectionTrackingConfidence: Float = 0.3
        ) {
            self.minimumSubjectConfidence = minimumSubjectConfidence
            self.minimumJointConfidence = minimumJointConfidence
            self.detectsBodyPose = detectsBodyPose
            self.minimumSelectionTrackingConfidence = minimumSelectionTrackingConfidence
        }

        public static let `default` = Options()
    }

    private let options: Options
    private let tracker: SubjectTracker
    private var selectionTracking: ActiveSelectionTracking?

    private struct ActiveSelectionTracking {
        let id: UInt64
        let request: TrackObjectRequest
    }

    private struct DetectionResult {
        let subjects: [SubjectObservation]
        let selectionTracking: SelectionTrackingObservation?
    }

    public init(options: Options = .default) {
        self.options = options
        tracker = SubjectTracker()
    }

    /// Starts local tracking from the AI plan's selected source region.
    ///
    /// The region is image-space only. This does not claim a world coordinate or a
    /// physical distance; it simply follows the pixels that described the selection.
    public func beginSelectionTracking(id: UInt64, region: ForgeCore.NormalizedRect) {
        guard region.isWellFormed, region.width > 0, region.height > 0 else {
            selectionTracking = nil
            return
        }

        let seed = DetectedObjectObservation(boundingBox: region.visionRect)
        selectionTracking = ActiveSelectionTracking(
            id: id,
            request: TrackObjectRequest(detectedObject: seed)
        )
    }

    public func clearSelectionTracking() {
        selectionTracking = nil
    }

    public func analyze(
        _ frame: SceneFrame<PixelBufferFrame>,
        previous: SceneState?
    ) async -> SceneState {
        let detection = await detect(in: frame.content)

        // Identity is assigned here rather than by Vision: guidance that jumps
        // between people is worse than no guidance, so a detection has to be matched
        // to whoever it most plausibly continues.
        let subjects = await tracker.track(
            detection.subjects,
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
            camera: nil,
            selectionTracking: detection.selectionTracking
        )
    }

    // MARK: - Vision

    /// One handler, every request. Vision shares work across requests in a single
    /// pass, so batching costs less than issuing them separately.
    private func detect(in content: PixelBufferFrame) async -> DetectionResult {
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
                if let activeTracking = selectionTracking {
                    let (humans, poses, trackedSelection) = try await handler.perform(
                        humanRequest,
                        poseRequest,
                        activeTracking.request
                    )
                    return DetectionResult(
                        subjects: merge(humans: humans, poses: poses),
                        selectionTracking: consume(
                            trackedSelection,
                            for: activeTracking.id
                        )
                    )
                }
                let (humans, poses) = try await handler.perform(humanRequest, poseRequest)
                return DetectionResult(
                    subjects: merge(humans: humans, poses: poses),
                    selectionTracking: nil
                )
            }

            if let activeTracking = selectionTracking {
                let (humans, trackedSelection) = try await handler.perform(
                    humanRequest,
                    activeTracking.request
                )
                return DetectionResult(
                    subjects: merge(humans: humans, poses: []),
                    selectionTracking: consume(trackedSelection, for: activeTracking.id)
                )
            }
            let humans = try await handler.perform(humanRequest)
            return DetectionResult(
                subjects: merge(humans: humans, poses: []),
                selectionTracking: nil
            )
        } catch {
            // A frame that cannot be analyzed yields an empty scene rather than
            // stopping the pipeline. The next frame is a fraction of a second away.
            let failedTracking = consumeFailedSelectionTracking()
            return DetectionResult(subjects: [], selectionTracking: failedTracking)
        }
    }

    private func consumeFailedSelectionTracking() -> SelectionTrackingObservation? {
        guard let trackingID = selectionTracking?.id else { return nil }
        return consume(nil, for: trackingID)
    }

    /// Accepts a result only if it still belongs to the active generation. Actor
    /// reentrancy allows a newer plan to arrive while Vision is processing a frame;
    /// an older result must never replace that newer track.
    private func consume(
        _ observation: DetectedObjectObservation?,
        for trackingID: UInt64
    ) -> SelectionTrackingObservation? {
        guard let activeTracking = selectionTracking,
              activeTracking.id == trackingID
        else {
            return nil
        }

        guard let observation,
              observation.confidence >= options.minimumSelectionTrackingConfidence
        else {
            return SelectionTrackingObservation(
                trackingID: trackingID,
                bounds: nil,
                confidence: 0
            )
        }

        return SelectionTrackingObservation(
            trackingID: trackingID,
            bounds: observation.boundingBox.forgeRect,
            confidence: Double(observation.confidence)
        )
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
