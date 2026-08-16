import Foundation

/// Decides when to ask the director for a new plan.
///
/// The AI planner runs orders of magnitude slower than perception, so it is driven by
/// events rather than by frames. Pure: time is supplied by the caller and all state is
/// threaded through explicitly, so a recorded session replays identically.
public struct PlanTrigger: Sendable {
    public let policy: PlanTriggerPolicy

    public init(policy: PlanTriggerPolicy = .default) {
        self.policy = policy
    }

    /// Why a replan was requested. Useful in logs and in tuning the policy — a session
    /// dominated by `subjectMoved` means the threshold is too tight.
    public enum Reason: String, Sendable, Equatable, CaseIterable {
        case noPlan
        case planExpired
        case userRequested
        case captureCompleted
        case subjectCountChanged
        case subjectMoved
        case subjectResized
        case lightingChanged
        case cameraMoved
        case focalLengthChanged
    }

    /// Things that happened since the last evaluation.
    public struct Events: Sendable, Equatable {
        public var userRequested: Bool
        public var captureCompleted: Bool

        public init(userRequested: Bool = false, captureCompleted: Bool = false) {
            self.userRequested = userRequested
            self.captureCompleted = captureCompleted
        }

        public static let none = Events()
    }

    /// Carried by the caller between frames so the trigger itself stays pure.
    public struct State: Sendable, Equatable {
        /// When the currently latched plan was issued.
        public var planIssuedAt: TimeInterval?
        /// When a request was last sent, for the rate cap.
        public var lastRequestAt: TimeInterval?
        /// The scene as it looked when the last request was sent.
        public var sceneAtLastRequest: SceneState?
        /// Whether a request is outstanding. New requests coalesce rather than queue.
        public var hasRequestInFlight: Bool

        public init(
            planIssuedAt: TimeInterval? = nil,
            lastRequestAt: TimeInterval? = nil,
            sceneAtLastRequest: SceneState? = nil,
            hasRequestInFlight: Bool = false
        ) {
            self.planIssuedAt = planIssuedAt
            self.lastRequestAt = lastRequestAt
            self.sceneAtLastRequest = sceneAtLastRequest
            self.hasRequestInFlight = hasRequestInFlight
        }

        public static let initial = State()
    }

    public struct Decision: Sendable, Equatable {
        public let shouldRequest: Bool
        public let reason: Reason?
        public let state: State
    }

    /// Evaluates one frame.
    ///
    /// `scene.timestamp` is the clock. Nothing here reads the wall clock, which is what
    /// makes replay deterministic.
    public func evaluate(
        scene: SceneState,
        plan: CompositionPlan?,
        events: Events = .none,
        state: State
    ) -> Decision {
        let now = scene.timestamp

        // A request is already outstanding. Further triggers coalesce into it rather
        // than queueing, so a busy scene cannot produce a backlog of stale plans.
        guard !state.hasRequestInFlight else {
            return Decision(shouldRequest: false, reason: nil, state: state)
        }

        guard let reason = reason(for: scene, plan: plan, events: events, state: state) else {
            return Decision(shouldRequest: false, reason: nil, state: state)
        }

        // An explicit user request always wins and resets the limiter — a person who
        // taps a button and gets nothing concludes the app is broken.
        if reason != .userRequested, isRateLimited(now: now, state: state) {
            return Decision(shouldRequest: false, reason: nil, state: state)
        }

        var next = state
        next.lastRequestAt = now
        next.sceneAtLastRequest = scene
        next.hasRequestInFlight = true

        return Decision(shouldRequest: true, reason: reason, state: next)
    }

    /// Records that a request finished, whether it produced a plan or failed.
    ///
    /// Failure still clears the in-flight flag: a dropped request must not wedge the
    /// trigger permanently.
    public func requestCompleted(
        at time: TimeInterval,
        producedPlan: Bool,
        state: State
    ) -> State {
        var next = state
        next.hasRequestInFlight = false
        if producedPlan {
            next.planIssuedAt = time
        }
        return next
    }

    // MARK: - Reasons

    private func reason(
        for scene: SceneState,
        plan: CompositionPlan?,
        events: Events,
        state: State
    ) -> Reason? {
        if events.userRequested {
            return .userRequested
        }
        if events.captureCompleted {
            return .captureCompleted
        }

        guard let plan, let issuedAt = state.planIssuedAt else { return .noPlan }

        let lifetime = plan.expiresAfterSeconds ?? policy.defaultPlanLifetime
        if scene.timestamp - issuedAt >= lifetime {
            return .planExpired
        }

        guard let previous = state.sceneAtLastRequest else { return nil }
        return materialChange(from: previous, to: scene)
    }

    /// Scores the difference between two scenes.
    ///
    /// A pure function of two `SceneState`s, which makes it trivially testable and is
    /// the knob that actually controls AI spend.
    public func materialChange(from previous: SceneState, to current: SceneState) -> Reason? {
        if previous.subjects.count != current.subjects.count {
            return .subjectCountChanged
        }

        if let before = previous.primarySubject, let after = current.primarySubject {
            let movement = distance(before.bounds.center, after.bounds.center)
            if movement >= policy.subjectMovementThreshold {
                return .subjectMoved
            }

            if before.bounds.height > 0 {
                let sizeChange = abs(after.bounds.height - before.bounds.height) / before.bounds
                    .height
                if sizeChange >= policy.subjectSizeChangeThreshold {
                    return .subjectResized
                }
            }
        }

        if let before = previous.lighting, let after = current.lighting {
            let stops = abs(after.exposureDifference(from: before))
            if stops >= policy.exposureChangeThresholdEV {
                return .lightingChanged
            }
        }

        if
            let before = previous.motion?.position,
            let after = current.motion?.position,
            before.provenance.isMetric, after.provenance.isMetric {
            if distance(before.value, after.value) >= policy.cameraMovementThreshold {
                return .cameraMoved
            }
        }

        if
            let before = previous.camera?.focalLength,
            let after = current.camera?.focalLength,
            before > 0 {
            if abs(after - before) / before >= policy.focalLengthChangeThreshold {
                return .focalLengthChanged
            }
        }

        return nil
    }

    // MARK: - Helpers

    private func isRateLimited(now: TimeInterval, state: State) -> Bool {
        guard let last = state.lastRequestAt else { return false }
        return now - last < policy.minimumRequestInterval
    }

    private func distance(_ lhs: NormalizedPoint, _ rhs: NormalizedPoint) -> Double {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return (dx * dx + dy * dy).squareRoot()
    }

    private func distance(_ lhs: Vector3, _ rhs: Vector3) -> Double {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        let dz = lhs.z - rhs.z
        return (dx * dx + dy * dy + dz * dz).squareRoot()
    }
}
