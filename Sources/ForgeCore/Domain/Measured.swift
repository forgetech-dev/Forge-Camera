import Foundation

/// Where a spatial measurement came from.
///
/// Provenance decides whether a value may ever be shown to the user with real-world
/// units. Promoting an estimate to a measurement is the single most likely way this
/// project betrays its users, so the distinction is carried in the type rather than
/// left to the discipline of the caller.
public enum MeasurementProvenance: String, Sendable, Equatable, Codable, CaseIterable {
    /// Direct depth from a LiDAR sensor.
    case lidar
    /// Depth derived from an AR session's scene depth.
    case arkitDepth
    /// Translation derived from tracked AR camera pose.
    case arkitPose
    /// Derived from camera intrinsics together with a genuinely known real-world size.
    case intrinsics
    /// Inferred from image cues alone, such as apparent face size. **Not metric.**
    case estimated
    /// Entered by the user, for example a manually supplied subject distance.
    case userProvided

    /// Whether a value from this source may be expressed in real-world units.
    public var isMetric: Bool {
        switch self {
        case .lidar, .arkitDepth, .arkitPose, .intrinsics, .userProvided:
            true
        case .estimated:
            false
        }
    }
}

/// A value paired with how well it is known and where it came from.
///
/// The guidance engine reads `isTrustworthyMetric` to decide whether a cue may carry
/// units. A value that fails that check still informs relative magnitude — it simply
/// never prints a number.
public struct Measured<Value: Sendable & Equatable>: Sendable, Equatable {
    public let value: Value
    /// Confidence in `[0, 1]`.
    public let confidence: Double
    public let provenance: MeasurementProvenance

    public init(value: Value, confidence: Double, provenance: MeasurementProvenance) {
        self.value = value
        self.confidence = confidence.clampedToUnitInterval
        self.provenance = provenance
    }

    /// A measurement is usable as metric only when its source is metric *and* the
    /// estimate is confident enough to act on.
    public func isTrustworthyMetric(minimumConfidence: Double) -> Bool {
        provenance.isMetric && confidence >= minimumConfidence
    }

    public func map<T: Sendable & Equatable>(_ transform: (Value) -> T) -> Measured<T> {
        Measured<T>(value: transform(value), confidence: confidence, provenance: provenance)
    }
}

extension Measured: Codable where Value: Codable {}

public extension Measured where Value == Double {
    /// Convenience for a value known only from image cues.
    static func estimated(_ value: Double, confidence: Double) -> Measured<Double> {
        Measured(value: value, confidence: confidence, provenance: .estimated)
    }
}
