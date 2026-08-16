import Foundation

/// A deterministic, offline director built from classical composition rules.
///
/// This one implementation does two jobs. It is the graceful-degradation path when
/// there is no AI backend, no key, and no network — and it is the test double every
/// guidance and replay test runs against. Sharing one implementation means offline
/// behaviour cannot drift from what the tests exercise, and it means a genuinely
/// useful product exists before any AI does.
///
/// Deliberately not clever. It applies thirds placement, lead room, headroom, and
/// level horizon, and it never claims more confidence than a rule deserves.
public struct HeuristicDirector: DirectorProvider {
    public struct Rules: Sendable, Equatable {
        /// Thirds line the subject is placed on when there is a reason to go off-centre.
        public var thirdsOffset: Double
        /// Subject height, as a fraction of the frame, per intent.
        public var portraitSubjectHeight: Double
        public var environmentalSubjectHeight: Double
        /// How far above centre a subject's centre sits, so the head is not cramped.
        public var headroomLift: Double
        /// Horizon placement for landscape work.
        public var landscapeHorizonY: Double
        /// Yaw beyond which the subject is considered to be facing meaningfully sideways,
        /// so lead room applies.
        public var leadRoomYawThreshold: Angle

        public init(
            thirdsOffset: Double = 1.0 / 3.0,
            portraitSubjectHeight: Double = 0.7,
            environmentalSubjectHeight: Double = 0.4,
            headroomLift: Double = 0.06,
            landscapeHorizonY: Double = 1.0 / 3.0,
            leadRoomYawThreshold: Angle = .degrees(12)
        ) {
            self.thirdsOffset = thirdsOffset
            self.portraitSubjectHeight = portraitSubjectHeight
            self.environmentalSubjectHeight = environmentalSubjectHeight
            self.headroomLift = headroomLift
            self.landscapeHorizonY = landscapeHorizonY
            self.leadRoomYawThreshold = leadRoomYawThreshold
        }

        public static let `default` = Rules()
    }

    public let rules: Rules

    public init(rules: Rules = .default) {
        self.rules = rules
    }

    public func plan(_ request: DirectorRequest) async throws -> CompositionPlan {
        makePlan(for: request)
    }

    /// Synchronous entry point, so tests and the guidance loop can call it without
    /// an await and without any concurrency in the way of determinism.
    public func makePlan(for request: DirectorRequest) -> CompositionPlan {
        let scene = request.scene
        let intent = request.intentHint ?? inferIntent(from: scene)

        return CompositionPlan(
            planId: "heuristic-\(request.requestId)",
            requestId: request.requestId,
            intent: intent,
            confidence: 0.5,
            rationale: rationale(for: intent),
            subject: subjectPlan(for: scene, intent: intent),
            scene: scenePlan(for: scene, intent: intent),
            camera: nil,
            exposure: exposurePlan(for: scene),
            capture: nil,
            expiresAfterSeconds: 20
        )
    }

    // MARK: - Intent

    private func inferIntent(from scene: SceneState) -> PhotographicIntent {
        let people = scene.subjects.filter { $0.kind == .person }
        guard let primary = people.first else { return .landscape }
        if people.count > 2 {
            return .group
        }
        // A subject occupying little of the frame is being photographed in a place,
        // not as a study of the person.
        return primary.bounds.height < 0.5 ? .environmentalPortrait : .portrait
    }

    // MARK: - Subject

    private func subjectPlan(for scene: SceneState, intent: PhotographicIntent) -> SubjectPlan? {
        guard let subject = scene.primarySubject, subject.kind == .person else { return nil }

        let targetHeight: Double = switch intent {
        case .portrait, .group:
            rules.portraitSubjectHeight
        case .environmentalPortrait, .street:
            rules.environmentalSubjectHeight
        case .landscape, .architecture, .unknown:
            rules.environmentalSubjectHeight
        }

        return SubjectPlan(
            targetX: targetX(for: subject),
            targetY: 0.5 - rules.headroomLift,
            targetHeight: targetHeight
        )
    }

    /// Places the subject on a thirds line, giving lead room in the direction they face.
    ///
    /// A subject looking toward frame-left is placed right of centre so the gaze has
    /// somewhere to go. With no reliable orientation, the subject stays where the
    /// nearest thirds line is, which avoids commanding a move for no reason.
    private func targetX(for subject: DetectedSubject) -> Double {
        let leftThird = rules.thirdsOffset
        let rightThird = 1 - rules.thirdsOffset

        guard let orientation = subject.faceOrientation, orientation.confidence >= 0.5 else {
            return subject.bounds.center.x < 0.5 ? leftThird : rightThird
        }

        let yaw = orientation.yaw.wrapped()
        guard yaw.magnitude >= rules.leadRoomYawThreshold.magnitude else {
            return subject.bounds.center.x < 0.5 ? leftThird : rightThird
        }

        // Positive yaw is counter-clockwise viewed from above, so the subject is
        // turned toward frame-left and belongs on the right third.
        return yaw.degrees > 0 ? rightThird : leftThird
    }

    // MARK: - Scene

    private func scenePlan(for scene: SceneState, intent: PhotographicIntent) -> ScenePlan? {
        guard scene.horizon != nil else { return nil }
        switch intent {
        case .landscape, .architecture, .street:
            return ScenePlan(targetHorizon: rules.landscapeHorizonY)
        case .portrait, .environmentalPortrait, .group, .unknown:
            // Keeping the horizon where it is avoids fighting the portrait framing.
            return nil
        }
    }

    // MARK: - Exposure

    private func exposurePlan(for scene: SceneState) -> ExposurePlan? {
        guard let lighting = scene.lighting else { return nil }
        // Meaningful clipping means highlights are the thing at risk; otherwise the
        // subject is what should be correctly exposed.
        let priority: ExposurePriority = lighting.clippedHighlightFraction > 0.05
            ? .highlights
            : .subject
        return ExposurePlan(priority: priority)
    }

    private func rationale(for intent: PhotographicIntent) -> String {
        switch intent {
        case .portrait:
            "Portrait framing: subject on a thirds line with headroom."
        case .environmentalPortrait:
            "Environmental portrait: smaller subject to keep the surroundings visible."
        case .group:
            "Group: wider framing so everyone stays in frame."
        case .landscape:
            "Landscape: level horizon placed on the upper third."
        case .street, .architecture, .unknown:
            "Composed on thirds with a level horizon."
        }
    }
}
