import Foundation

/// Turns the director's exposure *intent* into concrete values the camera can accept.
///
/// The split matters: the director says what should be protected ("the subject", "the
/// highlights", "freeze the motion") without knowing the sensor, and this engine turns
/// that into numbers clamped to what the connected camera can actually deliver. One
/// plan therefore works on a phone and on a mirrorless body with a different ISO set.
///
/// Pure, and does no camera I/O. It returns a recommendation; a controller decides
/// whether to apply it based on the user's chosen control level.
public struct ExposureEngine: Sendable {
    public let policy: ExposurePolicy

    public init(policy: ExposurePolicy = .default) {
        self.policy = policy
    }

    /// Collects what the engine could not deliver as it resolves each parameter.
    ///
    /// One accumulator rather than a pair of `inout` arrays that always travel
    /// together, and it puts the clamp-and-record step in a single place.
    struct Outcome {
        var manualRequests: [ExposureParameter] = []
        var clamped: [ExposureParameter] = []

        /// Clamps a desired value to a control and records both consequences.
        mutating func resolve(
            _ desired: Double,
            with control: ExposureCapabilities.Control,
            as parameter: ExposureParameter
        ) -> Double {
            let value = control.clamp(desired)
            if value != desired {
                clamped.append(parameter)
            }
            if !control.isWritable {
                manualRequests.append(parameter)
            }
            return value
        }
    }

    public func recommendation(
        for scene: SceneState,
        intent: ExposurePlan?,
        capabilities: ExposureCapabilities
    ) -> ExposureRecommendation {
        let priority = resolvedPriority(intent: intent, scene: scene)

        var outcome = Outcome()

        let shutter = resolveShutter(
            priority: priority,
            intent: intent,
            scene: scene,
            capabilities: capabilities,
            outcome: &outcome
        )
        let aperture = resolveAperture(
            priority: priority,
            intent: intent,
            capabilities: capabilities,
            outcome: &outcome
        )
        let iso = resolveISO(
            priority: priority,
            scene: scene,
            capabilities: capabilities,
            outcome: &outcome
        )

        return ExposureRecommendation(
            settings: ExposureSettings(
                iso: iso,
                shutterDenominator: shutter,
                aperture: aperture
            ),
            manualRequests: outcome.manualRequests,
            clamped: outcome.clamped
        )
    }

    // MARK: - Priority

    /// Falls back to what the scene itself suggests when the director had no opinion.
    ///
    /// Blown highlights are unrecoverable, so they outrank an unstated preference.
    private func resolvedPriority(intent: ExposurePlan?, scene: SceneState) -> ExposurePriority {
        // `isKnown` pattern matches. Comparing against `.unknown(rawValue)` would not
        // work here: RawRepresentable derives `==` from rawValue, so such a check is
        // always false. See the note on ExposurePriority.
        if let stated = intent?.priority, stated.isKnown {
            return stated
        }
        if
            let lighting = scene.lighting,
            lighting.clippedHighlightFraction > policy.highlightClippingThreshold {
            return .highlights
        }
        return scene.primarySubject != nil ? .subject : .balanced
    }

    // MARK: - Shutter

    /// The shutter floor, from the reciprocal rule and any request from the plan.
    ///
    /// Never slower than handheld safety allows: a correctly exposed blurred frame is
    /// still a failed photograph.
    private func resolveShutter(
        priority: ExposurePriority,
        intent: ExposurePlan?,
        scene: SceneState,
        capabilities: ExposureCapabilities,
        outcome: inout Outcome
    ) -> Double? {
        var floor = handheldFloor(for: scene)

        if let requested = intent?.minShutterDenominator, requested > 0 {
            floor = Swift.max(floor, requested)
        }
        if priority == .motion {
            floor = Swift.max(floor, policy.motionFreezeShutterDenominator)
        }

        guard let control = capabilities.shutterDenominator else { return nil }

        return outcome.resolve(floor, with: control, as: .shutter)
    }

    /// 1/(focal length × safety factor), or a fixed fallback when focal length is unknown.
    private func handheldFloor(for scene: SceneState) -> Double {
        guard let focalLength = scene.camera?.focalLength, focalLength > 0 else {
            return policy.fallbackMinimumShutterDenominator
        }
        return focalLength * policy.handheldShutterSafetyFactor
    }

    // MARK: - Aperture

    private func resolveAperture(
        priority: ExposurePriority,
        intent: ExposurePlan?,
        capabilities: ExposureCapabilities,
        outcome: inout Outcome
    ) -> Double? {
        guard let control = capabilities.aperture else { return nil }

        let desired: Double = if let hint = intent?.apertureHint, hint > 0 {
            hint
        } else {
            switch priority {
            case .depth: policy.defaultDepthAperture
            case .subject: policy.defaultSubjectAperture
            case .highlights, .motion, .balanced, .unknown: control.supportedRange.lowerBound
            }
        }

        return outcome.resolve(desired, with: control, as: .aperture)
    }

    // MARK: - ISO

    /// ISO absorbs whatever the shutter and aperture decisions left over.
    ///
    /// Without a metering reading this cannot be computed properly, so the engine
    /// biases from scene brightness rather than pretending to a number it cannot know.
    private func resolveISO(
        priority: ExposurePriority,
        scene: SceneState,
        capabilities: ExposureCapabilities,
        outcome: inout Outcome
    ) -> Double? {
        guard let control = capabilities.iso else { return nil }

        var desired = scene.camera?.iso ?? control.supportedRange.lowerBound

        if priority == .highlights {
            // Pull exposure down to keep highlights recoverable.
            desired /= pow(2, policy.highlightProtectionEV)
        }
        desired = Swift.min(desired, policy.preferredMaximumISO)

        return outcome.resolve(desired, with: control, as: .iso)
    }
}
