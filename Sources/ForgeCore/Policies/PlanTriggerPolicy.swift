import Foundation

/// When the AI director is allowed to be asked for a new plan.
///
/// This is the main lever on both AI cost and how stable guidance feels. Replanning
/// too eagerly is not merely expensive: the user experiences a target that keeps
/// moving while they are trying to reach it, which reads as the system changing its
/// mind.
public struct PlanTriggerPolicy: Sendable, Equatable {
    /// How long a plan stays fresh when it does not carry its own lifetime.
    public var defaultPlanLifetime: TimeInterval

    /// Shortest gap between two requests. The hard rate cap.
    public var minimumRequestInterval: TimeInterval

    /// Subject centre movement, as a fraction of the frame, that counts as material.
    public var subjectMovementThreshold: Double

    /// Subject size change, as a fraction of its previous height, that counts as material.
    public var subjectSizeChangeThreshold: Double

    /// Scene brightness change in stops that counts as material.
    public var exposureChangeThresholdEV: Double

    /// Camera translation in metres that counts as material.
    public var cameraMovementThreshold: Double

    /// Focal length change, as a fraction of the previous value, that counts as material.
    public var focalLengthChangeThreshold: Double

    public init(
        defaultPlanLifetime: TimeInterval = 20,
        minimumRequestInterval: TimeInterval = 0.5,
        subjectMovementThreshold: Double = 0.15,
        subjectSizeChangeThreshold: Double = 0.25,
        exposureChangeThresholdEV: Double = 1.0,
        cameraMovementThreshold: Double = 0.5,
        focalLengthChangeThreshold: Double = 0.1
    ) {
        self.defaultPlanLifetime = defaultPlanLifetime
        self.minimumRequestInterval = minimumRequestInterval
        self.subjectMovementThreshold = subjectMovementThreshold
        self.subjectSizeChangeThreshold = subjectSizeChangeThreshold
        self.exposureChangeThresholdEV = exposureChangeThresholdEV
        self.cameraMovementThreshold = cameraMovementThreshold
        self.focalLengthChangeThreshold = focalLengthChangeThreshold
    }

    public static let `default` = PlanTriggerPolicy()

    /// The maximum request rate this policy permits, in hertz.
    public var maximumRequestRate: Double {
        minimumRequestInterval > 0 ? 1 / minimumRequestInterval : .infinity
    }
}
