import Foundation

/// Turns the gap between the current scene and the latched plan into a small number
/// of things the user should do.
///
/// Pure: no I/O, no clock, no randomness, no logging side effects. State is carried
/// explicitly in `MemoryState` and threaded through by the caller, so replaying a
/// recorded session reproduces byte-identical output.
///
/// The individual cue rules live in `GuidanceEngine+Cues.swift`; this file owns the
/// orchestration, ranking, and the shared tolerance helpers.
public struct GuidanceEngine: Sendable {
    public let policy: GuidancePolicy

    public init(policy: GuidancePolicy = .default) {
        self.policy = policy
    }

    /// Which cues were active last frame.
    ///
    /// Hysteresis needs to know what was already being said: a satisfied cue must stay
    /// silent until the error grows past the wider exit tolerance, not the narrow one
    /// it just crossed.
    public struct MemoryState: Sendable, Equatable {
        var activeAxes: Set<GuidanceAxis>

        public init(activeAxes: Set<GuidanceAxis> = []) {
            self.activeAxes = activeAxes
        }

        public static let initial = MemoryState()
    }

    public struct Output: Sendable, Equatable {
        public let guidance: GuidanceState
        public let memory: MemoryState
    }

    /// A cue that cleared its tolerance, before ranking decides whether it survives.
    struct Candidate {
        let cue: GuidanceCue
        /// Error expressed as a multiple of its own tolerance, so unlike quantities
        /// (degrees, fractions of a frame) can be compared on one scale.
        let normalizedError: Double
    }

    /// Collects cues as the rules run.
    ///
    /// Exists so a rule takes one accumulator rather than a pair of `inout` parameters
    /// that always travel together — the axis set and the candidate list are only ever
    /// written as a unit.
    struct Candidates {
        private(set) var all: [Candidate] = []
        private(set) var activeAxes: Set<GuidanceAxis> = []

        mutating func add(_ candidate: Candidate) {
            all.append(candidate)
            activeAxes.insert(candidate.cue.axis)
        }

        var isEmpty: Bool {
            all.isEmpty
        }
    }

    /// Computes guidance for one frame.
    public func guidance(
        for scene: SceneState,
        plan: CompositionPlan?,
        memory: MemoryState = .initial
    ) -> Output {
        guard let plan else {
            return Output(guidance: .idle(), memory: .initial)
        }

        var candidates = Candidates()
        let subject = scene.subjects.first { $0.salience >= policy.minimumDetectionConfidence }

        if let subject, let subjectPlan = plan.subject {
            appendPlacementCues(
                subject: subject,
                subjectPlan: subjectPlan,
                scene: scene,
                memory: memory,
                into: &candidates
            )
            appendSizeCue(
                subject: subject,
                subjectPlan: subjectPlan,
                memory: memory,
                into: &candidates
            )
            appendBodyYawCue(
                subject: subject,
                subjectPlan: subjectPlan,
                memory: memory,
                into: &candidates
            )
        }

        if subject != nil, let cameraPlan = plan.camera {
            appendHeightCue(cameraPlan: cameraPlan, memory: memory, into: &candidates)
        }

        if let horizon = scene.horizon {
            appendLevellingCue(horizon: horizon, memory: memory, into: &candidates)
        }

        if let cameraPlan = plan.camera {
            appendFocalLengthCue(
                cameraPlan: cameraPlan,
                scene: scene,
                memory: memory,
                into: &candidates
            )
        }

        let cues = rank(candidates.all)

        return Output(
            guidance: GuidanceState(
                planId: plan.planId,
                cues: cues,
                readiness: readiness(from: cues, hadCandidates: !candidates.isEmpty),
                overlay: overlay(for: scene, plan: plan),
                displayAdvice: plan.displayAdvice ?? []
            ),
            memory: MemoryState(activeAxes: candidates.activeAxes)
        )
    }

    // MARK: - Ranking

    private func rank(_ candidates: [Candidate]) -> [GuidanceCue] {
        let sorted = candidates.sorted { lhs, rhs in
            if lhs.cue.priority != rhs.cue.priority {
                return lhs.cue.priority > rhs.cue.priority
            }
            if lhs.normalizedError != rhs.normalizedError {
                return lhs.normalizedError > rhs.normalizedError
            }
            // Deterministic tie-break so replay output is stable.
            return lhs.cue.axis.rawValue < rhs.cue.axis.rawValue
        }

        var perActor: [GuidanceActor: Int] = [:]
        var result: [GuidanceCue] = []

        for candidate in sorted {
            guard result.count < policy.maximumCues else { break }
            let used = perActor[candidate.cue.actor, default: 0]
            guard used < policy.maximumCuesPerActor else { continue }
            perActor[candidate.cue.actor] = used + 1
            result.append(candidate.cue)
        }

        return result
    }

    private func readiness(from cues: [GuidanceCue], hadCandidates: Bool) -> Readiness {
        guard let blocking = cues.first else {
            return hadCandidates ? .close : .ready
        }
        return .blocked(blocking)
    }

    private func overlay(for scene: SceneState, plan: CompositionPlan) -> OverlayModel {
        OverlayModel(
            visualAnchor: plan.selection?.visualAnchor,
            targetFrame: plan.framing?.targetFrame,
            targetHorizonY: plan.scene?.targetHorizon,
            currentHorizonY: scene.horizon?.normalizedY,
            avoidRegions: plan.scene?.avoidRegions ?? []
        )
    }

    // MARK: - Shared helpers

    /// Deadband plus hysteresis in one decision.
    ///
    /// A silent axis has to clear the *wider* exit tolerance before it starts speaking,
    /// while an axis already speaking keeps speaking until the error falls below the
    /// *narrower* enter tolerance. The gap between the two is what stops a cue
    /// flickering on and off while the user hovers at the boundary.
    func exceedsTolerance(
        _ error: Double,
        enter: Double,
        exit: Double,
        wasActive: Bool
    ) -> Bool {
        wasActive ? error > enter : error > exit
    }

    func relativeMagnitude(_ error: Double, tolerance: Double) -> GuidanceMagnitude.Relative {
        guard tolerance > 0 else { return .moderate }
        let multiple = error / tolerance
        if multiple >= policy.largeErrorMultiple {
            return .large
        }
        if multiple >= policy.moderateErrorMultiple {
            return .moderate
        }
        return .slight
    }
}
