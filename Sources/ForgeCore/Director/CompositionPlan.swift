import Foundation

/// What the photograph should be.
///
/// Produced by a `DirectorProvider`, validated before it is ever trusted, then
/// latched: guidance reads the current plan every frame. A slow, failed, or absent
/// plan never stalls the loop.
///
/// **Absent is not zero.** Every optional field distinguishes "the director has no
/// opinion" from "the director says zero". Decoding a missing field to a default of
/// `0` collapses those and produces confidently wrong guidance.
public struct CompositionPlan: Sendable, Equatable, Codable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let planId: String
    public let requestId: String?
    public let intent: PhotographicIntent
    public let confidence: Double?
    /// Human-readable justification.
    ///
    /// **Display-only.** No engine, view model, or test may branch on its content.
    /// This is the enforcement of "free-text AI responses are never application state".
    public let rationale: String?
    /// What the Director proposes the photograph should be about.
    public let selection: SubjectSelection?
    /// The proposed photograph boundary, independent of any detection bounds.
    public let framing: FramingPlan?
    /// Short, display-only suggestions for the live view.
    ///
    /// No engine, view model, or test may branch on their wording.
    public let displayAdvice: [String]?
    public let subject: SubjectPlan?
    public let scene: ScenePlan?
    public let camera: CameraPlan?
    public let exposure: ExposurePlan?
    public let capture: CapturePlan?
    /// How long this plan stays fresh before a replan is due.
    public let expiresAfterSeconds: Double?

    public init(
        schemaVersion: Int = CompositionPlan.currentSchemaVersion,
        planId: String,
        requestId: String? = nil,
        intent: PhotographicIntent,
        confidence: Double? = nil,
        rationale: String? = nil,
        selection: SubjectSelection? = nil,
        framing: FramingPlan? = nil,
        displayAdvice: [String]? = nil,
        subject: SubjectPlan? = nil,
        scene: ScenePlan? = nil,
        camera: CameraPlan? = nil,
        exposure: ExposurePlan? = nil,
        capture: CapturePlan? = nil,
        expiresAfterSeconds: Double? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.planId = planId
        self.requestId = requestId
        self.intent = intent
        self.confidence = confidence
        self.rationale = rationale
        self.selection = selection
        self.framing = framing
        self.displayAdvice = displayAdvice
        self.subject = subject
        self.scene = scene
        self.camera = camera
        self.exposure = exposure
        self.capture = capture
        self.expiresAfterSeconds = expiresAfterSeconds
    }

    /// Whether this plan is still fresh at the given moment.
    public func isFresh(
        at now: TimeInterval,
        issuedAt: TimeInterval,
        defaultLifetime: Double
    ) -> Bool {
        let lifetime = expiresAfterSeconds ?? defaultLifetime
        return (now - issuedAt) < lifetime
    }
}

// MARK: - Plan sections

/// A Director-selected photographic subject or scene theme in the planning image.
///
/// `sourceRegion` and `visualAnchor` seed local tracking. The AI does not provide the
/// runtime `SubjectID`; local perception owns identity after the selection is accepted.
public struct SubjectSelection: Sendable, Equatable, Codable {
    public let kind: PhotographicSubjectKind
    /// A human-readable name such as "cat" or "window light".
    ///
    /// Display-only. Application logic must use `kind` and geometry instead.
    public let label: String?
    /// Region containing the selection in Forge normalized planning-image space.
    /// A scene-level theme may legitimately have no discrete region.
    public let sourceRegion: NormalizedRect?
    /// The compositional attention point in Forge normalized planning-image space.
    /// This is not automatically an autofocus point.
    public let visualAnchor: NormalizedPoint?
    public let confidence: Double?

    public init(
        kind: PhotographicSubjectKind,
        label: String? = nil,
        sourceRegion: NormalizedRect? = nil,
        visualAnchor: NormalizedPoint? = nil,
        confidence: Double? = nil
    ) {
        self.kind = kind
        self.label = label
        self.sourceRegion = sourceRegion
        self.visualAnchor = visualAnchor
        self.confidence = confidence
    }

    private enum CodingKeys: String, CodingKey {
        case kind, label, sourceRegion, visualAnchor, confidence
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(PhotographicSubjectKind.self, forKey: .kind)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        sourceRegion = try container.decodeIfPresent(NormalizedRect.self, forKey: .sourceRegion)
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)

        if container.contains(.visualAnchor), try !container.decodeNil(forKey: .visualAnchor) {
            var point = try container.nestedUnkeyedContainer(forKey: .visualAnchor)
            let x = try point.decode(Double.self)
            let y = try point.decode(Double.self)
            visualAnchor = NormalizedPoint(x: x, y: y)
        } else {
            visualAnchor = nil
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(label, forKey: .label)
        try container.encodeIfPresent(sourceRegion, forKey: .sourceRegion)
        try container.encodeIfPresent(confidence, forKey: .confidence)
        if let visualAnchor {
            var point = container.nestedUnkeyedContainer(forKey: .visualAnchor)
            try point.encode(visualAnchor.x)
            try point.encode(visualAnchor.y)
        }
    }
}

/// The boundary of the photograph the Director proposes making.
public struct FramingPlan: Sendable, Equatable, Codable {
    /// Target photograph boundary in Forge normalized planning-image space.
    ///
    /// This is deliberately independent of `SubjectSelection.sourceRegion`: one says
    /// what was selected, while the other says what the final photograph should include.
    public let targetFrame: NormalizedRect?

    public init(targetFrame: NormalizedRect? = nil) {
        self.targetFrame = targetFrame
    }
}

public struct SubjectPlan: Sendable, Equatable, Codable {
    /// Target horizontal position of the subject's centre, in Forge normalized space.
    public let targetX: Double?
    /// Target vertical position of the subject's centre, in Forge normalized space.
    public let targetY: Double?
    /// Target subject height as a fraction of frame height.
    public let targetHeight: Double?
    /// Target body facing direction; `0` faces the camera.
    public let bodyYaw: Angle?
    /// Target head facing direction, relative to the camera.
    public let headYaw: Angle?
    public let poseHint: PoseHint?

    public init(
        targetX: Double? = nil,
        targetY: Double? = nil,
        targetHeight: Double? = nil,
        bodyYaw: Angle? = nil,
        headYaw: Angle? = nil,
        poseHint: PoseHint? = nil
    ) {
        self.targetX = targetX
        self.targetY = targetY
        self.targetHeight = targetHeight
        self.bodyYaw = bodyYaw
        self.headYaw = headYaw
        self.poseHint = poseHint
    }

    public var targetCentre: NormalizedPoint? {
        guard let targetX, let targetY else { return nil }
        return NormalizedPoint(x: targetX, y: targetY)
    }
}

public struct ScenePlan: Sendable, Equatable, Codable {
    /// Target normalized y of the horizon line.
    public let targetHorizon: Double?
    /// Regions that should not contain the subject or distracting content.
    public let avoidRegions: [NormalizedRect]?

    public init(targetHorizon: Double? = nil, avoidRegions: [NormalizedRect]? = nil) {
        self.targetHorizon = targetHorizon
        self.avoidRegions = avoidRegions
    }
}

public struct CameraPlan: Sendable, Equatable, Codable {
    /// Camera height change as a **fraction of the subject's on-screen height**.
    ///
    /// Deliberately dimensionless: a director looking at a single image can judge
    /// "lower by about 15% of the subject's height" reliably, but cannot know how
    /// many centimetres that is. Units are attached later, only if earned.
    public let heightAdjustment: Double?
    /// Additional camera yaw requested by the director.
    public let yawAdjustment: Angle?
    /// Suggested 35mm-equivalent focal length in millimetres.
    public let recommendedFocalLength: Double?

    public init(
        heightAdjustment: Double? = nil,
        yawAdjustment: Angle? = nil,
        recommendedFocalLength: Double? = nil
    ) {
        self.heightAdjustment = heightAdjustment
        self.yawAdjustment = yawAdjustment
        self.recommendedFocalLength = recommendedFocalLength
    }
}

/// Exposure *intent*, never concrete values.
///
/// The director says what matters; `ExposureEngine` turns that into values clamped to
/// what the connected camera can actually do. This is what lets one plan work on a
/// phone and on a mirrorless body with a different sensor.
public struct ExposurePlan: Sendable, Equatable, Codable {
    public let priority: ExposurePriority?
    public let apertureHint: Double?
    public let minShutterDenominator: Double?

    public init(
        priority: ExposurePriority? = nil,
        apertureHint: Double? = nil,
        minShutterDenominator: Double? = nil
    ) {
        self.priority = priority
        self.apertureHint = apertureHint
        self.minShutterDenominator = minShutterDenominator
    }
}

public struct CapturePlan: Sendable, Equatable, Codable {
    public let kind: CaptureKind
    /// Exposure offsets in stops, for a bracket.
    public let stops: [Double]?

    public init(kind: CaptureKind, stops: [Double]? = nil) {
        self.kind = kind
        self.stops = stops
    }
}

// MARK: - Forward-compatible enumerations

//
// Unknown values decode to `.unknown` and are ignored by engines, so a director can
// introduce a new intent without a schema bump and without breaking older clients.

/// The broad photographic role of the Director's selected subject or theme.
public enum PhotographicSubjectKind: Sendable, Equatable, Codable, RawRepresentable {
    case person
    case animal
    case object
    case place
    case scene
    case light
    case relationship
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "person": self = .person
        case "animal": self = .animal
        case "object": self = .object
        case "place": self = .place
        case "scene": self = .scene
        case "light": self = .light
        case "relationship": self = .relationship
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .person: "person"
        case .animal: "animal"
        case .object: "object"
        case .place: "place"
        case .scene: "scene"
        case .light: "light"
        case .relationship: "relationship"
        case let .unknown(raw): raw
        }
    }
}

public enum PhotographicIntent: Sendable, Equatable, Codable, RawRepresentable {
    case portrait
    case environmentalPortrait
    case landscape
    case street
    case architecture
    case group
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "portrait": self = .portrait
        case "environmental_portrait": self = .environmentalPortrait
        case "landscape": self = .landscape
        case "street": self = .street
        case "architecture": self = .architecture
        case "group": self = .group
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .portrait: "portrait"
        case .environmentalPortrait: "environmental_portrait"
        case .landscape: "landscape"
        case .street: "street"
        case .architecture: "architecture"
        case .group: "group"
        case let .unknown(raw): raw
        }
    }

    public var isKnown: Bool {
        if case .unknown = self {
            return false
        }
        return true
    }
}

/// Note on comparing these forward-compatible enums.
///
/// They are `RawRepresentable`, and the standard library derives `==` from `rawValue`
/// for such types. That makes `.depth == .unknown("depth")` **true**, so a check like
/// `value != .unknown(value.rawValue)` is always false and silently does nothing.
/// Detect an unrecognised case with the `isKnown` pattern match instead.
public enum ExposurePriority: Sendable, Equatable, Codable, RawRepresentable {
    case subject
    case highlights
    case motion
    case depth
    case balanced
    case unknown(String)

    public var isKnown: Bool {
        if case .unknown = self {
            return false
        }
        return true
    }

    public init(rawValue: String) {
        switch rawValue {
        case "subject": self = .subject
        case "highlights": self = .highlights
        case "motion": self = .motion
        case "depth": self = .depth
        case "balanced": self = .balanced
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .subject: "subject"
        case .highlights: "highlights"
        case .motion: "motion"
        case .depth: "depth"
        case .balanced: "balanced"
        case let .unknown(raw): raw
        }
    }
}

public enum CaptureKind: Sendable, Equatable, Codable, RawRepresentable {
    case single
    case bracket
    case focusStack
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "single": self = .single
        case "bracket": self = .bracket
        case "focus_stack": self = .focusStack
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .single: "single"
        case .bracket: "bracket"
        case .focusStack: "focus_stack"
        case let .unknown(raw): raw
        }
    }
}

public enum PoseHint: Sendable, Equatable, Codable, RawRepresentable {
    case weightOnBackFoot
    case turnShoulders
    case relaxArms
    case chinForward
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "weight_on_back_foot": self = .weightOnBackFoot
        case "turn_shoulders": self = .turnShoulders
        case "relax_arms": self = .relaxArms
        case "chin_forward": self = .chinForward
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .weightOnBackFoot: "weight_on_back_foot"
        case .turnShoulders: "turn_shoulders"
        case .relaxArms: "relax_arms"
        case .chinForward: "chin_forward"
        case let .unknown(raw): raw
        }
    }
}

// MARK: - Angle coding

//
// Angles travel over the wire as plain degree numbers, not as an object.

public extension Angle {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(degrees: container.decode(Double.self))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(degrees)
    }
}

// MARK: - Normalized geometry coding

//
// Plan regions travel as compact arrays, which is what a model produces most
// reliably. `SubjectSelection` owns the same compact representation for its anchor;
// the domain-wide `NormalizedPoint` coding used by recorded scene state is unchanged.

public extension NormalizedRect {
    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let x = try container.decode(Double.self)
        let y = try container.decode(Double.self)
        let width = try container.decode(Double.self)
        let height = try container.decode(Double.self)
        self.init(x: x, y: y, width: width, height: height)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(x)
        try container.encode(y)
        try container.encode(width)
        try container.encode(height)
    }
}
