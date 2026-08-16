import Foundation

/// The three exposure parameters, named so a cue can say which one it means.
public enum ExposureParameter: String, Sendable, Equatable, CaseIterable {
    case iso
    case shutter
    case aperture
}

/// What a connected camera can actually do with one exposure parameter.
///
/// Read and write are separate: a camera that reports its aperture may still refuse to
/// change it, and the same body refuses different things in different exposure modes.
/// `nil` for a parameter means "not reported at all", which is not the same as
/// "reported but fixed".
public struct ExposureCapabilities: Sendable, Equatable {
    public struct Control: Sendable, Equatable {
        public let supportedRange: ClosedRange<Double>
        public let isWritable: Bool

        public init(supportedRange: ClosedRange<Double>, isWritable: Bool) {
            self.supportedRange = supportedRange
            self.isWritable = isWritable
        }

        /// Snaps a requested value into what the hardware supports.
        public func clamp(_ value: Double) -> Double {
            Swift.min(Swift.max(value, supportedRange.lowerBound), supportedRange.upperBound)
        }
    }

    public let iso: Control?
    /// Expressed as a denominator: 250 means 1/250 s. Larger is faster.
    public let shutterDenominator: Control?
    /// Expressed as an f-number. Larger is a smaller opening.
    public let aperture: Control?

    public init(iso: Control? = nil, shutterDenominator: Control? = nil, aperture: Control? = nil) {
        self.iso = iso
        self.shutterDenominator = shutterDenominator
        self.aperture = aperture
    }

    /// A camera that reports nothing and accepts nothing.
    ///
    /// The engine must still produce something useful against this, because it is what
    /// an unknown or disconnected camera looks like.
    public static let none = ExposureCapabilities()

    /// A phone-like camera: full auto exposure, nothing directly writable.
    public static let automatic = ExposureCapabilities(
        iso: Control(supportedRange: 20 ... 6400, isWritable: false),
        shutterDenominator: Control(supportedRange: 1 ... 8000, isWritable: false),
        aperture: Control(supportedRange: 1.8 ... 1.8, isWritable: false)
    )

    public func control(for parameter: ExposureParameter) -> Control? {
        switch parameter {
        case .iso: iso
        case .shutter: shutterDenominator
        case .aperture: aperture
        }
    }
}

/// Concrete exposure values.
///
/// Absent means the engine has no opinion about that parameter, not zero.
public struct ExposureSettings: Sendable, Equatable {
    public let iso: Double?
    public let shutterDenominator: Double?
    public let aperture: Double?

    public init(iso: Double? = nil, shutterDenominator: Double? = nil, aperture: Double? = nil) {
        self.iso = iso
        self.shutterDenominator = shutterDenominator
        self.aperture = aperture
    }

    public static let empty = ExposureSettings()
}

/// What the exposure engine decided, and what it could not do.
public struct ExposureRecommendation: Sendable, Equatable {
    /// Values the app may apply itself.
    public let settings: ExposureSettings
    /// Parameters the user has to change on the camera body, because the app cannot.
    public let manualRequests: [ExposureParameter]
    /// Values the engine wanted but the hardware could not deliver.
    public let clamped: [ExposureParameter]

    public init(
        settings: ExposureSettings,
        manualRequests: [ExposureParameter] = [],
        clamped: [ExposureParameter] = []
    ) {
        self.settings = settings
        self.manualRequests = manualRequests
        self.clamped = clamped
    }

    public static let none = ExposureRecommendation(settings: .empty)
}
