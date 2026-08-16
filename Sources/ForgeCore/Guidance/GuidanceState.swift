import Foundation

/// Who a cue is addressed to.
///
/// In phone mode the photographer and the camera move together; on a tripod they do
/// not. A user who moves themselves when they should have moved the subject has been
/// failed by the interface, so the distinction is carried explicitly.
public enum GuidanceActor: String, Sendable, Equatable, Codable, CaseIterable {
    case photographer
    case subject
    case camera
}

/// What kind of correction a cue asks for.
public enum GuidanceAxis: String, Sendable, Equatable, Codable {
    case left, right, up, down
    /// Toward the subject, along the optical axis.
    case forward
    /// Away from the subject, along the optical axis.
    case backward
    /// Rotate the camera horizontally.
    case panLeft, panRight
    /// Rotate the camera vertically.
    case tiltUp, tiltDown
    /// Level the camera about the optical axis.
    case rollLevel
    /// Rotate the subject's body.
    case rotateBodyLeft, rotateBodyRight
    case focalLength
}

/// How large a correction is.
///
/// There is deliberately no bare `Double` here. A cue built without metric provenance
/// **cannot** carry metres, so no renderer can print "40 cm" for a quantity that was
/// never measured. Any code that would need to "just convert" a relative magnitude
/// into metres is a bug being written.
public enum GuidanceMagnitude: Sendable, Equatable {
    case metric(meters: Double, confidence: Double)
    case relative(Relative)

    public enum Relative: Int, Sendable, Equatable, Comparable, CaseIterable {
        case slight = 0
        case moderate = 1
        case large = 2

        public static func < (lhs: Relative, rhs: Relative) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public var isMetric: Bool {
        if case .metric = self {
            return true
        }
        return false
    }
}

/// An angular correction, which is metric-accurate far more often than a distance is.
///
/// Roll and pitch come free and exact from gravity, so levelling guidance can be
/// precise even when every distance in the frame is only relative.
public enum GuidanceRotation: Sendable, Equatable {
    case degrees(Angle, confidence: Double)
    case relative(GuidanceMagnitude.Relative)
}

/// One thing the user should do.
public struct GuidanceCue: Sendable, Equatable {
    public let actor: GuidanceActor
    public let axis: GuidanceAxis
    public let magnitude: GuidanceMagnitude
    public let rotation: GuidanceRotation?
    /// Higher sorts first. Combined with normalized error to rank cues.
    public let priority: Int
    /// True when the app cannot make this change itself and is asking the user to.
    public let manualRequest: Bool

    public init(
        actor: GuidanceActor,
        axis: GuidanceAxis,
        magnitude: GuidanceMagnitude,
        rotation: GuidanceRotation? = nil,
        priority: Int,
        manualRequest: Bool = false
    ) {
        self.actor = actor
        self.axis = axis
        self.magnitude = magnitude
        self.rotation = rotation
        self.priority = priority
        self.manualRequest = manualRequest
    }
}

/// How close the current framing is to the plan.
public enum Readiness: Sendable, Equatable {
    /// Something material is still wrong; the blocking cue is carried along.
    case blocked(GuidanceCue)
    /// Within reach but not yet inside tolerance.
    case close
    /// Inside tolerance on every axis the plan expressed an opinion about.
    case ready

    public var isReady: Bool {
        self == .ready
    }
}

/// What the overlay should draw, derived from the plan rather than from the error.
///
/// Showing the target as well as the gap lets the user solve the problem themselves,
/// which is faster than following corrections one at a time.
public struct OverlayModel: Sendable, Equatable {
    /// Where the subject should be, if the plan said.
    public let targetSubjectBounds: NormalizedRect?
    /// Where the subject currently is.
    public let currentSubjectBounds: NormalizedRect?
    /// Target normalized y of the horizon.
    public let targetHorizonY: Double?
    /// Current normalized y of the horizon.
    public let currentHorizonY: Double?
    public let avoidRegions: [NormalizedRect]

    public init(
        targetSubjectBounds: NormalizedRect? = nil,
        currentSubjectBounds: NormalizedRect? = nil,
        targetHorizonY: Double? = nil,
        currentHorizonY: Double? = nil,
        avoidRegions: [NormalizedRect] = []
    ) {
        self.targetSubjectBounds = targetSubjectBounds
        self.currentSubjectBounds = currentSubjectBounds
        self.targetHorizonY = targetHorizonY
        self.currentHorizonY = currentHorizonY
        self.avoidRegions = avoidRegions
    }

    public static let empty = OverlayModel()
}

/// The complete instruction to the interface for one frame.
///
/// Cues arrive pre-ranked and pre-filtered: the view renders what it is given and
/// applies no smoothing of its own, because view-layer animation that disguises
/// jitter hides a real bug and adds latency.
public struct GuidanceState: Sendable, Equatable {
    public let planId: String?
    public let cues: [GuidanceCue]
    public let readiness: Readiness
    public let overlay: OverlayModel

    public init(
        planId: String?,
        cues: [GuidanceCue],
        readiness: Readiness,
        overlay: OverlayModel
    ) {
        self.planId = planId
        self.cues = cues
        self.readiness = readiness
        self.overlay = overlay
    }

    /// Nothing to say — no plan, or no subject to guide toward one.
    public static func idle(planId: String? = nil) -> GuidanceState {
        GuidanceState(planId: planId, cues: [], readiness: .close, overlay: .empty)
    }

    public func cue(for actor: GuidanceActor) -> GuidanceCue? {
        cues.first { $0.actor == actor }
    }
}
