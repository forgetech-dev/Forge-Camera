import Foundation

/// Tunable constants for turning exposure intent into values.
public struct ExposurePolicy: Sendable, Equatable {
    /// Multiplier on the reciprocal-rule shutter floor.
    ///
    /// The classic rule is 1/focal-length for a steady hand. Modern sensors and
    /// pixel-peeping make that optimistic, so the default is twice as fast.
    public var handheldShutterSafetyFactor: Double

    /// Shutter floor when the focal length is unknown, as a denominator.
    public var fallbackMinimumShutterDenominator: Double

    /// Shutter denominator considered fast enough to freeze ordinary human movement.
    public var motionFreezeShutterDenominator: Double

    /// Highlight clipping above this fraction means highlights are genuinely at risk.
    public var highlightClippingThreshold: Double

    /// Exposure reduction applied when protecting highlights, in stops.
    public var highlightProtectionEV: Double

    /// Aperture used for subject separation when the plan gives no hint.
    public var defaultSubjectAperture: Double

    /// Aperture used when the plan asks for depth and gives no hint.
    public var defaultDepthAperture: Double

    /// ISO the engine prefers to stay at or below before trading away shutter speed.
    public var preferredMaximumISO: Double

    public init(
        handheldShutterSafetyFactor: Double = 2,
        fallbackMinimumShutterDenominator: Double = 60,
        motionFreezeShutterDenominator: Double = 250,
        highlightClippingThreshold: Double = 0.05,
        highlightProtectionEV: Double = 1,
        defaultSubjectAperture: Double = 2.8,
        defaultDepthAperture: Double = 8,
        preferredMaximumISO: Double = 3200
    ) {
        self.handheldShutterSafetyFactor = handheldShutterSafetyFactor
        self.fallbackMinimumShutterDenominator = fallbackMinimumShutterDenominator
        self.motionFreezeShutterDenominator = motionFreezeShutterDenominator
        self.highlightClippingThreshold = highlightClippingThreshold
        self.highlightProtectionEV = highlightProtectionEV
        self.defaultSubjectAperture = defaultSubjectAperture
        self.defaultDepthAperture = defaultDepthAperture
        self.preferredMaximumISO = preferredMaximumISO
    }

    public static let `default` = ExposurePolicy()
}
