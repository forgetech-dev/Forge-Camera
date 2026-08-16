import Foundation

/// An angle stored in degrees.
///
/// The project convention is degrees, positive counter-clockwise by the right-hand
/// rule, with `0` meaning "facing the camera" for subject orientation. This type
/// exists so that degrees and radians cannot be silently mixed: trigonometry needs
/// radians, the domain speaks degrees, and the conversion is named at every use.
public struct Angle: Sendable, Equatable, Codable, Comparable {
    public var degrees: Double

    public init(degrees: Double) {
        self.degrees = degrees
    }

    public static func degrees(_ value: Double) -> Angle {
        Angle(degrees: value)
    }

    public static func radians(_ value: Double) -> Angle {
        Angle(degrees: value * 180 / .pi)
    }

    public var radians: Double {
        degrees * .pi / 180
    }

    public static let zero = Angle(degrees: 0)

    /// Wraps into `(-180, 180]`.
    ///
    /// Guidance always wants the shortest rotation to a target, so a request to turn
    /// 350° becomes a request to turn -10°.
    public func wrapped() -> Angle {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value <= -180 {
            value += 360
        }
        if value > 180 {
            value -= 360
        }
        // -0.0 and 0.0 compare equal but print differently; normalise for stable output.
        return Angle(degrees: value == 0 ? 0 : value)
    }

    public var magnitude: Double {
        Swift.abs(degrees)
    }

    public static func < (lhs: Angle, rhs: Angle) -> Bool {
        lhs.degrees < rhs.degrees
    }

    public static func - (lhs: Angle, rhs: Angle) -> Angle {
        Angle(degrees: lhs.degrees - rhs.degrees)
    }

    public static func + (lhs: Angle, rhs: Angle) -> Angle {
        Angle(degrees: lhs.degrees + rhs.degrees)
    }

    public static prefix func - (angle: Angle) -> Angle {
        Angle(degrees: -angle.degrees)
    }
}

extension Angle: CustomStringConvertible {
    public var description: String {
        String(format: "%.1f°", degrees)
    }
}

// MARK: - Field of view

/// A camera's angular field of view, used to convert image positions into angles.
///
/// Without this, angular guidance is impossible and cues must degrade to relative
/// magnitudes — which is the documented behaviour when focal length is unknown.
public struct FieldOfView: Sendable, Equatable, Codable {
    public let horizontal: Angle
    public let vertical: Angle

    public init(horizontal: Angle, vertical: Angle) {
        self.horizontal = horizontal
        self.vertical = vertical
    }

    /// Derives a field of view from a horizontal angle and the frame's aspect ratio.
    public init?(horizontal: Angle, aspectRatio: Double) {
        guard aspectRatio > 0, horizontal.degrees > 0, horizontal.degrees < 180 else { return nil }
        let verticalRadians = 2 * atan(tan(horizontal.radians / 2) / aspectRatio)
        self.init(horizontal: horizontal, vertical: .radians(verticalRadians))
    }

    /// The angle from the optical axis to a normalized horizontal position.
    ///
    /// Exact for a pinhole camera: `yaw(x) = atan((2x - 1) * tan(θ/2))`.
    /// Positive x beyond centre yields a positive angle.
    public func horizontalAngle(atNormalizedX x: Double) -> Angle {
        Self.angle(atNormalized: x, acrossFieldOfView: horizontal)
    }

    /// The angle from the optical axis to a normalized vertical position.
    ///
    /// Note the sign: Forge y increases downward, so a position below centre is a
    /// downward (negative) tilt.
    public func verticalAngle(atNormalizedY y: Double) -> Angle {
        -Self.angle(atNormalized: y, acrossFieldOfView: vertical)
    }

    private static func angle(atNormalized value: Double, acrossFieldOfView fov: Angle) -> Angle {
        let halfExtent = tan(fov.radians / 2)
        return .radians(atan((2 * value - 1) * halfExtent))
    }
}
