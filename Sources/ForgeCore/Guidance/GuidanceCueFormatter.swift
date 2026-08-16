import Foundation

/// Turns a cue into the words the user reads.
///
/// This lives in the domain rather than the UI layer because it is pure, has no UI
/// dependency, and is the single point where "never fabricate precision" becomes
/// visible text. Keeping it here means `swift test` covers it on every machine, with
/// no simulator and no device.
///
/// Units exist only here. Everything upstream is metres and degrees.
public struct GuidanceCueFormatter: Sendable {
    public enum UnitSystem: Sendable, Equatable {
        case metric
        case imperial
    }

    public let units: UnitSystem

    public init(units: UnitSystem = .metric) {
        self.units = units
    }

    /// The instruction text for a cue.
    ///
    /// A `.relative` magnitude never produces a number, because there is no number to
    /// produce. The switch is exhaustive over the magnitude, so a future case cannot
    /// silently fall through to a fabricated measurement.
    public func text(for cue: GuidanceCue) -> String {
        let action = action(for: cue.axis)

        switch cue.magnitude {
        case let .metric(meters, _):
            if cue.axis == .focalLength {
                // Focal length is carried in the metric case but is millimetres, not a
                // distance to move. It is a request to change lens.
                return "\(action) \(Int(meters.rounded())) mm"
            }
            return "\(action) \(distanceText(meters))"

        case let .relative(relative):
            switch relative {
            case .slight: return "\(action) a little"
            case .moderate: return action
            case .large: return "\(action) a lot"
            }
        }
    }

    /// A short label suitable for a compact HUD readout.
    public func shortText(for cue: GuidanceCue) -> String {
        switch cue.magnitude {
        case let .metric(meters, _):
            cue.axis == .focalLength
                ? "\(Int(meters.rounded()))mm"
                : "\(symbol(for: cue.axis)) \(distanceText(meters))"
        case let .relative(relative):
            "\(symbol(for: cue.axis))\(String(repeating: "·", count: relative.rawValue + 1))"
        }
    }

    /// The rotation text for a cue, when it has one.
    ///
    /// Angles are metric far more often than distances are, because gravity supplies
    /// roll exactly and a known field of view supplies pan and tilt exactly.
    public func rotationText(for cue: GuidanceCue) -> String? {
        guard let rotation = cue.rotation else { return nil }
        switch rotation {
        case let .degrees(angle, _):
            let magnitude = angle.magnitude
            guard magnitude >= 0.5 else { return nil }
            return "\(Int(magnitude.rounded()))°"
        case .relative:
            // Deliberately no text: the arrow already carries direction, and inventing
            // a number here is exactly the failure this project refuses.
            return nil
        }
    }

    public func text(for readiness: Readiness) -> String {
        switch readiness {
        case .ready: "Ready"
        case .close: "Almost"
        case let .blocked(cue): text(for: cue)
        }
    }

    // MARK: - Pieces

    private func distanceText(_ meters: Double) -> String {
        switch units {
        case .metric:
            if meters < 1 {
                return "\(Int((meters * 100).rounded())) cm"
            }
            return String(format: "%.1f m", meters)
        case .imperial:
            let inches = meters * 39.3701
            if inches < 12 {
                return "\(Int(inches.rounded())) in"
            }
            return String(format: "%.1f ft", inches / 12)
        }
    }

    private func action(for axis: GuidanceAxis) -> String {
        switch axis {
        case .left: "Move left"
        case .right: "Move right"
        case .up: "Raise the camera"
        case .down: "Lower the camera"
        case .forward: "Step closer"
        case .backward: "Step back"
        case .panLeft: "Turn left"
        case .panRight: "Turn right"
        case .tiltUp: "Tilt up"
        case .tiltDown: "Tilt down"
        case .rollLevel: "Level the camera"
        case .rotateBodyLeft: "Turn your body left"
        case .rotateBodyRight: "Turn your body right"
        case .focalLength: "Switch to"
        }
    }

    private func symbol(for axis: GuidanceAxis) -> String {
        switch axis {
        case .left, .panLeft, .rotateBodyLeft: "←"
        case .right, .panRight, .rotateBodyRight: "→"
        case .up, .tiltUp: "↑"
        case .down, .tiltDown: "↓"
        case .forward: "⊕"
        case .backward: "⊖"
        case .rollLevel: "↻"
        case .focalLength: "⌗"
        }
    }
}
