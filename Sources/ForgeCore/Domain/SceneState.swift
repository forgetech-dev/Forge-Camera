import Foundation

/// A stable identity for a subject tracked across frames.
///
/// Guidance that jumps between people is worse than no guidance, so identity has to
/// survive frame-to-frame detection noise.
public struct SubjectID: Sendable, Equatable, Hashable, Codable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

public enum SubjectKind: Sendable, Equatable, Codable {
    case person
    case animal
    case object(label: String)
}

/// A subject's facing direction, in the project's angle convention.
public struct FaceOrientation: Sendable, Equatable, Codable {
    public let yaw: Angle
    public let pitch: Angle
    public let roll: Angle
    public let confidence: Double

    public init(yaw: Angle, pitch: Angle, roll: Angle, confidence: Double) {
        self.yaw = yaw
        self.pitch = pitch
        self.roll = roll
        self.confidence = confidence.clampedToUnitInterval
    }
}

/// A named skeletal joint with its own confidence.
///
/// Per-joint confidence is propagated rather than averaged away: pose guidance built
/// on a hallucinated skeleton is a real failure mode.
public struct BodyJoint: Sendable, Equatable, Codable {
    public enum Name: String, Sendable, Equatable, Codable, CaseIterable {
        case nose, neck
        case leftShoulder, rightShoulder
        case leftElbow, rightElbow
        case leftWrist, rightWrist
        case leftHip, rightHip
        case leftKnee, rightKnee
        case leftAnkle, rightAnkle
    }

    public let name: Name
    public let position: NormalizedPoint
    public let confidence: Double

    public init(name: Name, position: NormalizedPoint, confidence: Double) {
        self.name = name
        self.position = position
        self.confidence = confidence.clampedToUnitInterval
    }
}

public struct BodyPose: Sendable, Equatable, Codable {
    public let joints: [BodyJoint]

    public init(joints: [BodyJoint]) {
        self.joints = joints
    }

    public func joint(_ name: BodyJoint.Name) -> BodyJoint? {
        joints.first { $0.name == name }
    }

    /// Joints at or above a confidence floor.
    public func confidentJoints(minimumConfidence: Double) -> [BodyJoint] {
        joints.filter { $0.confidence >= minimumConfidence }
    }
}

/// One detected subject in a frame.
public struct DetectedSubject: Sendable, Equatable, Codable {
    public let id: SubjectID
    public let bounds: NormalizedRect
    public let kind: SubjectKind
    public let pose: BodyPose?
    public let faceOrientation: FaceOrientation?
    /// Distance in metres. Present only when genuinely measured or estimated —
    /// the provenance decides whether it may ever be shown with units.
    public let distance: Measured<Double>?
    /// Relative visual importance in `[0, 1]`; subjects are sorted by this.
    public let salience: Double

    public init(
        id: SubjectID,
        bounds: NormalizedRect,
        kind: SubjectKind = .person,
        pose: BodyPose? = nil,
        faceOrientation: FaceOrientation? = nil,
        distance: Measured<Double>? = nil,
        salience: Double = 1
    ) {
        self.id = id
        self.bounds = bounds
        self.kind = kind
        self.pose = pose
        self.faceOrientation = faceOrientation
        self.distance = distance
        self.salience = salience.clampedToUnitInterval
    }
}

/// The horizon line, as a normalized y position plus the roll needed to level it.
///
/// Roll comes free and exact from gravity, so this is one of the few metric-accurate
/// facts available with no depth and no AR session.
public struct HorizonEstimate: Sendable, Equatable, Codable {
    public let normalizedY: Double
    public let roll: Angle
    public let confidence: Double

    public init(normalizedY: Double, roll: Angle, confidence: Double) {
        self.normalizedY = normalizedY
        self.roll = roll
        self.confidence = confidence.clampedToUnitInterval
    }
}

/// Summary photometry for the frame.
public struct LightingEstimate: Sendable, Equatable, Codable {
    /// Mean luma in `[0, 1]`.
    public let meanLuma: Double
    /// Fraction of pixels at or near the top of the range.
    public let clippedHighlightFraction: Double
    /// Fraction of pixels at or near the bottom of the range.
    public let clippedShadowFraction: Double

    public init(meanLuma: Double, clippedHighlightFraction: Double, clippedShadowFraction: Double) {
        self.meanLuma = meanLuma.clampedToUnitInterval
        self.clippedHighlightFraction = clippedHighlightFraction.clampedToUnitInterval
        self.clippedShadowFraction = clippedShadowFraction.clampedToUnitInterval
    }

    /// Roughly log2 of the ratio between this frame's mean luma and another's.
    ///
    /// Used by the replan trigger to notice a material lighting change.
    public func exposureDifference(from other: LightingEstimate) -> Double {
        let floor = 0.001
        let mine = Swift.max(meanLuma, floor)
        let theirs = Swift.max(other.meanLuma, floor)
        return log2(mine / theirs)
    }
}

/// Whether the motion source describes the same physical body as the frame source.
///
/// An AR pose describes the *phone*. With an external camera on a tripod that has
/// nothing to do with the photograph, so metric photographer guidance requires an
/// explicit declaration that the two are rigidly coupled. `.unknown` fails safe.
public enum MotionCoupling: String, Sendable, Equatable, Codable {
    case rigid
    case decoupled
    case unknown

    public var allowsMetricPhotographerGuidance: Bool {
        self == .rigid
    }
}

public struct DeviceMotionState: Sendable, Equatable, Codable {
    /// Roll of the device about the optical axis.
    public let roll: Angle
    /// Pitch of the device.
    public let pitch: Angle
    /// Metric camera translation since the session origin, if tracking is healthy.
    public let position: Measured<Vector3>?
    public let coupling: MotionCoupling

    public init(
        roll: Angle,
        pitch: Angle,
        position: Measured<Vector3>? = nil,
        coupling: MotionCoupling = .unknown
    ) {
        self.roll = roll
        self.pitch = pitch
        self.position = position
        self.coupling = coupling
    }
}

public struct Vector3: Sendable, Equatable, Codable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
}

/// Camera settings and optics as reported for this frame.
///
/// Every field is optional, and absent means "not reported" — never zero.
public struct CameraState: Sendable, Equatable, Codable {
    /// 35mm-equivalent focal length in millimetres.
    public let focalLength: Double?
    public let fieldOfView: FieldOfView?
    public let aperture: Double?
    public let iso: Double?
    /// Shutter speed as a denominator: 250 means 1/250s.
    public let shutterDenominator: Double?

    public init(
        focalLength: Double? = nil,
        fieldOfView: FieldOfView? = nil,
        aperture: Double? = nil,
        iso: Double? = nil,
        shutterDenominator: Double? = nil
    ) {
        self.focalLength = focalLength
        self.fieldOfView = fieldOfView
        self.aperture = aperture
        self.iso = iso
        self.shutterDenominator = shutterDenominator
    }
}

/// Everything local perception knows about one frame.
///
/// Produced at frame rate by a `SceneAnalyzer`, consumed by the guidance engine and,
/// occasionally, summarised for the AI director.
public struct SceneState: Sendable, Equatable, Codable {
    /// Monotonic seconds from the frame's presentation timestamp. Never wall-clock.
    public let timestamp: TimeInterval
    public let frame: FrameGeometry
    /// Sorted by salience, descending.
    public let subjects: [DetectedSubject]
    public let horizon: HorizonEstimate?
    public let lighting: LightingEstimate?
    public let motion: DeviceMotionState?
    public let camera: CameraState?

    public init(
        timestamp: TimeInterval,
        frame: FrameGeometry,
        subjects: [DetectedSubject] = [],
        horizon: HorizonEstimate? = nil,
        lighting: LightingEstimate? = nil,
        motion: DeviceMotionState? = nil,
        camera: CameraState? = nil
    ) {
        self.timestamp = timestamp
        self.frame = frame
        self.subjects = subjects.sorted { $0.salience > $1.salience }
        self.horizon = horizon
        self.lighting = lighting
        self.motion = motion
        self.camera = camera
    }

    /// The subject guidance is currently about: the most salient one.
    public var primarySubject: DetectedSubject? {
        subjects.first
    }

    /// The effective field of view, preferring what the camera reported and falling
    /// back to deriving it from the frame's aspect ratio.
    public var effectiveFieldOfView: FieldOfView? {
        if let reported = camera?.fieldOfView {
            return reported
        }
        return nil
    }

    /// Whether metric photographer guidance is permitted for this frame.
    public var allowsMetricPhotographerGuidance: Bool {
        motion?.coupling.allowsMetricPhotographerGuidance ?? false
    }
}
