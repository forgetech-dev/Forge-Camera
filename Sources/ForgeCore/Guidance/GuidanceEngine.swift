import Foundation

/// Turns the gap between the current scene and the latched plan into a small number
/// of things the user should do.
///
/// Pure: no I/O, no clock, no randomness, no logging side effects. State is carried
/// explicitly in `MemoryState` and threaded through by the caller, so replaying a
/// recorded session reproduces byte-identical output.
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

    /// Computes guidance for one frame.
    public func guidance(
        for scene: SceneState,
        plan: CompositionPlan?,
        memory: MemoryState = .initial
    ) -> Output {
        guard let plan else {
            return Output(guidance: .idle(), memory: .initial)
        }

        var candidates: [Candidate] = []
        var nextActiveAxes: Set<GuidanceAxis> = []

        let subject = scene.subjects.first { $0.salience >= policy.minimumDetectionConfidence }

        if let subject, let subjectPlan = plan.subject {
            appendPlacementCues(
                subject: subject, subjectPlan: subjectPlan, scene: scene,
                memory: memory, into: &candidates, active: &nextActiveAxes
            )
            appendSizeCue(
                subject: subject, subjectPlan: subjectPlan,
                memory: memory, into: &candidates, active: &nextActiveAxes
            )
            appendBodyYawCue(
                subject: subject, subjectPlan: subjectPlan,
                memory: memory, into: &candidates, active: &nextActiveAxes
            )
        }

        if let subject, let cameraPlan = plan.camera {
            appendHeightCue(
                subject: subject, cameraPlan: cameraPlan,
                memory: memory, into: &candidates, active: &nextActiveAxes
            )
        }

        if let horizon = scene.horizon {
            appendLevellingCue(
                horizon: horizon, memory: memory, into: &candidates, active: &nextActiveAxes
            )
        }

        if let cameraPlan = plan.camera {
            appendFocalLengthCue(
                cameraPlan: cameraPlan, scene: scene,
                memory: memory, into: &candidates, active: &nextActiveAxes
            )
        }

        let cues = rank(candidates)
        let readiness = readiness(from: cues, hadCandidates: !candidates.isEmpty)
        let overlay = overlay(for: scene, plan: plan, subject: subject)

        return Output(
            guidance: GuidanceState(
                planId: plan.planId,
                cues: cues,
                readiness: readiness,
                overlay: overlay
            ),
            memory: MemoryState(activeAxes: nextActiveAxes)
        )
    }

    // MARK: - Subject placement

    //
    // A placement error is corrected by rotating the camera, not by stepping sideways.
    // Rotation is the cheapest correction and preserves perspective; lateral movement
    // is reserved for background conflicts, where changing the relationship between
    // subject and background is the actual goal.

    private func appendPlacementCues(
        subject: DetectedSubject,
        subjectPlan: SubjectPlan,
        scene: SceneState,
        memory: MemoryState,
        into candidates: inout [Candidate],
        active: inout Set<GuidanceAxis>
    ) {
        let current = subject.bounds.center

        if let targetX = subjectPlan.targetX {
            // Subject too far left in frame means the camera should pan left to
            // bring it toward centre-right of where it sits now.
            let error = targetX - current.x
            let axis: GuidanceAxis = error > 0 ? .panRight : .panLeft
            if let candidate = positionCandidate(
                error: error, axis: axis, actor: .photographer,
                priority: policy.subjectPlacementPriority,
                fieldOfView: scene.effectiveFieldOfView,
                angleAt: { fov in
                    fov.horizontalAngle(atNormalizedX: targetX)
                        - fov.horizontalAngle(atNormalizedX: current.x)
                },
                memory: memory
            ) {
                candidates.append(candidate)
                active.insert(axis)
            }
        }

        if let targetY = subjectPlan.targetY {
            let error = targetY - current.y
            // Forge y increases downward: a target below the subject needs a downward tilt.
            let axis: GuidanceAxis = error > 0 ? .tiltDown : .tiltUp
            if let candidate = positionCandidate(
                error: error, axis: axis, actor: .photographer,
                priority: policy.subjectPlacementPriority - 1,
                fieldOfView: scene.effectiveFieldOfView,
                angleAt: { fov in
                    fov.verticalAngle(atNormalizedY: targetY)
                        - fov.verticalAngle(atNormalizedY: current.y)
                },
                memory: memory
            ) {
                candidates.append(candidate)
                active.insert(axis)
            }
        }
    }

    private func positionCandidate(
        error: Double,
        axis: GuidanceAxis,
        actor: GuidanceActor,
        priority: Int,
        fieldOfView: FieldOfView?,
        angleAt: (FieldOfView) -> Angle,
        memory: MemoryState
    ) -> Candidate? {
        let magnitude = abs(error)
        guard exceedsTolerance(
            magnitude,
            enter: policy.positionEnterTolerance,
            exit: policy.positionExitTolerance,
            wasActive: memory.activeAxes.contains(axis)
        ) else { return nil }

        // With a known field of view the required rotation is exact; without one it
        // degrades to a relative magnitude rather than inventing a number.
        let rotation: GuidanceRotation = if let fieldOfView {
            .degrees(angleAt(fieldOfView).wrapped(), confidence: 1)
        } else {
            .relative(relativeMagnitude(magnitude, tolerance: policy.positionEnterTolerance))
        }

        return Candidate(
            cue: GuidanceCue(
                actor: actor,
                axis: axis,
                magnitude: .relative(
                    relativeMagnitude(magnitude, tolerance: policy.positionEnterTolerance)
                ),
                rotation: rotation,
                priority: priority
            ),
            normalizedError: magnitude / policy.positionEnterTolerance
        )
    }

    // MARK: - Subject size

    //
    // Size is corrected by moving, not zooming, unless the plan explicitly asked for a
    // different focal length. Moving changes perspective; zooming does not.
    //
    // The subject's real height cancels out of the ratio, so the *relative* move is
    // computable from image data alone. Metric scale is needed only for the final unit
    // conversion — which is why one code path produces both forms.

    private func appendSizeCue(
        subject: DetectedSubject,
        subjectPlan: SubjectPlan,
        memory: MemoryState,
        into candidates: inout [Candidate],
        active: inout Set<GuidanceAxis>
    ) {
        guard let targetHeight = subjectPlan.targetHeight, targetHeight > 0 else { return }
        let currentHeight = subject.bounds.height
        guard currentHeight > 0 else { return }

        let ratio = currentHeight / targetHeight
        let error = abs(ratio - 1)
        // Subject too small means the target is nearer than the current position.
        let axis: GuidanceAxis = ratio < 1 ? .forward : .backward

        guard exceedsTolerance(
            error,
            enter: policy.sizeEnterTolerance,
            exit: policy.sizeExitTolerance,
            wasActive: memory.activeAxes.contains(axis)
        ) else { return }

        let magnitude: GuidanceMagnitude
        if let distance = subject.distance,
           distance.isTrustworthyMetric(minimumConfidence: policy.minimumMetricConfidence) {
            // d_target / d_current = s_current / s_target
            let targetDistance = distance.value * ratio
            magnitude = .metric(
                meters: abs(targetDistance - distance.value),
                confidence: distance.confidence
            )
        } else {
            magnitude = .relative(relativeMagnitude(error, tolerance: policy.sizeEnterTolerance))
        }

        candidates.append(Candidate(
            cue: GuidanceCue(
                actor: .photographer,
                axis: axis,
                magnitude: magnitude,
                priority: policy.cameraDistancePriority
            ),
            normalizedError: error / policy.sizeEnterTolerance
        ))
        active.insert(axis)
    }

    // MARK: - Camera height

    //
    // heightAdjustment is a fraction of the subject's on-screen height, so it converts
    // to metres only when the subject's real height is independently known. It is not,
    // yet, so this always degrades to a relative cue — correctly.

    private func appendHeightCue(
        subject: DetectedSubject,
        cameraPlan: CameraPlan,
        memory: MemoryState,
        into candidates: inout [Candidate],
        active: inout Set<GuidanceAxis>
    ) {
        guard let adjustment = cameraPlan.heightAdjustment else { return }
        let error = abs(adjustment)
        let axis: GuidanceAxis = adjustment < 0 ? .down : .up

        guard exceedsTolerance(
            error,
            enter: policy.heightEnterTolerance,
            exit: policy.heightExitTolerance,
            wasActive: memory.activeAxes.contains(axis)
        ) else { return }

        candidates.append(Candidate(
            cue: GuidanceCue(
                actor: .camera,
                axis: axis,
                magnitude: .relative(relativeMagnitude(
                    error,
                    tolerance: policy.heightEnterTolerance
                )),
                priority: policy.cameraHeightPriority
            ),
            normalizedError: error / policy.heightEnterTolerance
        ))
        active.insert(axis)
    }

    // MARK: - Levelling

    //
    // Roll comes exactly from gravity, so this cue is metric-accurate even when every
    // distance in the frame is only relative.

    private func appendLevellingCue(
        horizon: HorizonEstimate,
        memory: MemoryState,
        into candidates: inout [Candidate],
        active: inout Set<GuidanceAxis>
    ) {
        let roll = horizon.roll.wrapped()
        let error = roll.magnitude

        guard exceedsTolerance(
            error,
            enter: policy.rollEnterTolerance.degrees,
            exit: policy.rollExitTolerance.degrees,
            wasActive: memory.activeAxes.contains(.rollLevel)
        ) else { return }

        candidates.append(Candidate(
            cue: GuidanceCue(
                actor: .camera,
                axis: .rollLevel,
                magnitude: .relative(
                    relativeMagnitude(error, tolerance: policy.rollEnterTolerance.degrees)
                ),
                rotation: .degrees(-roll, confidence: horizon.confidence),
                priority: policy.levellingPriority
            ),
            normalizedError: error / policy.rollEnterTolerance.degrees
        ))
        active.insert(.rollLevel)
    }

    // MARK: - Subject body yaw

    private func appendBodyYawCue(
        subject: DetectedSubject,
        subjectPlan: SubjectPlan,
        memory: MemoryState,
        into candidates: inout [Candidate],
        active: inout Set<GuidanceAxis>
    ) {
        guard let targetYaw = subjectPlan.bodyYaw,
              let orientation = subject.faceOrientation,
              orientation.confidence >= policy.minimumDetectionConfidence
        else { return }

        let delta = (targetYaw - orientation.yaw).wrapped()
        let error = delta.magnitude
        let axis: GuidanceAxis = delta.degrees > 0 ? .rotateBodyLeft : .rotateBodyRight

        guard exceedsTolerance(
            error,
            enter: policy.bodyYawEnterTolerance.degrees,
            exit: policy.bodyYawExitTolerance.degrees,
            wasActive: memory.activeAxes.contains(axis)
        ) else { return }

        candidates.append(Candidate(
            cue: GuidanceCue(
                actor: .subject,
                axis: axis,
                magnitude: .relative(
                    relativeMagnitude(error, tolerance: policy.bodyYawEnterTolerance.degrees)
                ),
                rotation: .degrees(delta, confidence: orientation.confidence),
                priority: policy.poseRefinementPriority
            ),
            normalizedError: error / policy.bodyYawEnterTolerance.degrees
        ))
        active.insert(axis)
    }

    // MARK: - Focal length

    //
    // The reference rig carries two primes and no zoom, so a focal-length change is a
    // request to the user, never a command to the camera.

    private func appendFocalLengthCue(
        cameraPlan: CameraPlan,
        scene: SceneState,
        memory: MemoryState,
        into candidates: inout [Candidate],
        active: inout Set<GuidanceAxis>
    ) {
        guard let recommended = cameraPlan.recommendedFocalLength,
              let current = scene.camera?.focalLength,
              current > 0
        else { return }

        let ratio = recommended / current
        guard abs(ratio - 1) > 0.1 else { return }

        candidates.append(Candidate(
            cue: GuidanceCue(
                actor: .camera,
                axis: .focalLength,
                magnitude: .metric(meters: recommended, confidence: 1),
                priority: policy.focalLengthPriority,
                manualRequest: true
            ),
            normalizedError: abs(ratio - 1)
        ))
        active.insert(.focalLength)
    }

    // MARK: - Ranking and readiness

    private struct Candidate {
        let cue: GuidanceCue
        /// Error expressed as a multiple of its own tolerance, so unlike quantities
        /// (degrees, fractions of a frame) can be compared on one scale.
        let normalizedError: Double
    }

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

    private func overlay(
        for scene: SceneState,
        plan: CompositionPlan,
        subject: DetectedSubject?
    ) -> OverlayModel {
        var targetBounds: NormalizedRect?
        if let subjectPlan = plan.subject,
           let centre = subjectPlan.targetCentre {
            let height = subjectPlan.targetHeight ?? subject?.bounds.height ?? 0
            let aspect = subject
                .map { $0.bounds.height > 0 ? $0.bounds.width / $0.bounds.height : 0.5 }
                ?? 0.5
            let width = height * aspect
            targetBounds = NormalizedRect(
                x: centre.x - width / 2,
                y: centre.y - height / 2,
                width: width,
                height: height
            )
        }

        return OverlayModel(
            targetSubjectBounds: targetBounds,
            currentSubjectBounds: subject?.bounds,
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
    private func exceedsTolerance(
        _ error: Double,
        enter: Double,
        exit: Double,
        wasActive: Bool
    ) -> Bool {
        wasActive ? error > enter : error > exit
    }

    private func relativeMagnitude(_ error: Double, tolerance: Double) -> GuidanceMagnitude
        .Relative {
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
