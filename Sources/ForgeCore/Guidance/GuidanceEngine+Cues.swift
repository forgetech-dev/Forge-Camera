import Foundation

/// The individual guidance rules.
///
/// Each rule reads the scene and the plan, decides whether its own axis is far enough
/// out of tolerance to be worth saying, and contributes at most one candidate. Ranking
/// and the cue budget are applied afterwards, in `GuidanceEngine.swift`.
extension GuidanceEngine {
    // MARK: - Subject placement

    //
    // A placement error is corrected by rotating the camera, not by stepping sideways.
    // Rotation is the cheapest correction and preserves perspective; lateral movement
    // is reserved for background conflicts, where changing the relationship between
    // subject and background is the actual goal.

    func appendPlacementCues(
        subject: DetectedSubject,
        subjectPlan: SubjectPlan,
        scene: SceneState,
        memory: MemoryState,
        into candidates: inout Candidates
    ) {
        let current = subject.bounds.center
        let fieldOfView = scene.effectiveFieldOfView

        if let targetX = subjectPlan.targetX {
            let error = targetX - current.x
            let axis: GuidanceAxis = error > 0 ? .panRight : .panLeft
            // With a known field of view the required rotation is exact; without one
            // it degrades to a relative magnitude rather than inventing a number.
            let rotation = rotation(magnitude: abs(error), fieldOfView: fieldOfView) { fov in
                fov.horizontalAngle(atNormalizedX: targetX)
                    - fov.horizontalAngle(atNormalizedX: current.x)
            }
            if let candidate = placementCandidate(
                error: error,
                axis: axis,
                priority: policy.subjectPlacementPriority,
                rotation: rotation,
                memory: memory
            ) {
                candidates.add(candidate)
            }
        }

        if let targetY = subjectPlan.targetY {
            let error = targetY - current.y
            // Forge y increases downward: a target below the subject needs a downward tilt.
            let axis: GuidanceAxis = error > 0 ? .tiltDown : .tiltUp
            let rotation = rotation(magnitude: abs(error), fieldOfView: fieldOfView) { fov in
                fov.verticalAngle(atNormalizedY: targetY)
                    - fov.verticalAngle(atNormalizedY: current.y)
            }
            if let candidate = placementCandidate(
                error: error,
                axis: axis,
                priority: policy.subjectPlacementPriority - 1,
                rotation: rotation,
                memory: memory
            ) {
                candidates.add(candidate)
            }
        }
    }

    private func rotation(
        magnitude: Double,
        fieldOfView: FieldOfView?,
        angle: (FieldOfView) -> Angle
    ) -> GuidanceRotation {
        guard let fieldOfView else {
            return .relative(relativeMagnitude(magnitude, tolerance: policy.positionEnterTolerance))
        }
        return .degrees(angle(fieldOfView).wrapped(), confidence: 1)
    }

    private func placementCandidate(
        error: Double,
        axis: GuidanceAxis,
        priority: Int,
        rotation: GuidanceRotation,
        memory: MemoryState
    ) -> Candidate? {
        let magnitude = abs(error)
        guard exceedsTolerance(
            magnitude,
            enter: policy.positionEnterTolerance,
            exit: policy.positionExitTolerance,
            wasActive: memory.activeAxes.contains(axis)
        ) else { return nil }

        return Candidate(
            cue: GuidanceCue(
                actor: .photographer,
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
    // conversion, which is why one code path produces both forms.

    func appendSizeCue(
        subject: DetectedSubject,
        subjectPlan: SubjectPlan,
        memory: MemoryState,
        into candidates: inout Candidates
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
        if
            let distance = subject.distance,
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

        candidates.add(Candidate(
            cue: GuidanceCue(
                actor: .photographer,
                axis: axis,
                magnitude: magnitude,
                priority: policy.cameraDistancePriority
            ),
            normalizedError: error / policy.sizeEnterTolerance
        ))
    }

    // MARK: - Camera height

    //
    // heightAdjustment is a fraction of the subject's on-screen height, so it converts
    // to metres only when the subject's real height is independently known. It is not,
    // yet, so this always degrades to a relative cue — correctly.

    func appendHeightCue(
        cameraPlan: CameraPlan,
        memory: MemoryState,
        into candidates: inout Candidates
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

        candidates.add(Candidate(
            cue: GuidanceCue(
                actor: .camera,
                axis: axis,
                magnitude: .relative(
                    relativeMagnitude(error, tolerance: policy.heightEnterTolerance)
                ),
                priority: policy.cameraHeightPriority
            ),
            normalizedError: error / policy.heightEnterTolerance
        ))
    }

    // MARK: - Levelling

    //
    // Roll comes exactly from gravity, so this cue is metric-accurate even when every
    // distance in the frame is only relative.

    func appendLevellingCue(
        horizon: HorizonEstimate,
        memory: MemoryState,
        into candidates: inout Candidates
    ) {
        let roll = horizon.roll.wrapped()
        let error = roll.magnitude

        guard exceedsTolerance(
            error,
            enter: policy.rollEnterTolerance.degrees,
            exit: policy.rollExitTolerance.degrees,
            wasActive: memory.activeAxes.contains(.rollLevel)
        ) else { return }

        candidates.add(Candidate(
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
    }

    // MARK: - Subject body yaw

    func appendBodyYawCue(
        subject: DetectedSubject,
        subjectPlan: SubjectPlan,
        memory: MemoryState,
        into candidates: inout Candidates
    ) {
        guard
            let targetYaw = subjectPlan.bodyYaw,
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

        candidates.add(Candidate(
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
    }

    // MARK: - Focal length

    //
    // The reference rig carries two primes and no zoom, so a focal-length change is a
    // request to the user, never a command to the camera.

    func appendFocalLengthCue(
        cameraPlan: CameraPlan,
        scene: SceneState,
        memory _: MemoryState,
        into candidates: inout Candidates
    ) {
        guard
            let recommended = cameraPlan.recommendedFocalLength,
            let current = scene.camera?.focalLength,
            current > 0
        else { return }

        let ratio = recommended / current
        guard abs(ratio - 1) > 0.1 else { return }

        candidates.add(Candidate(
            cue: GuidanceCue(
                actor: .camera,
                axis: .focalLength,
                magnitude: .metric(meters: recommended, confidence: 1),
                priority: policy.focalLengthPriority,
                manualRequest: true
            ),
            normalizedError: abs(ratio - 1)
        ))
    }
}
