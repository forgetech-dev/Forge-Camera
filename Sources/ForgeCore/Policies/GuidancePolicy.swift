import Foundation

/// Every tunable constant the guidance engine uses, in one place.
///
/// Named and centralised so they can be swept in replay tests rather than hunted
/// through the logic. No magic numbers live in the engine itself.
public struct GuidancePolicy: Sendable, Equatable {
    // MARK: Deadband and hysteresis

    /// Below this framing error, no cue is emitted. Expressed as a fraction of the frame.
    public var positionEnterTolerance: Double
    /// Once satisfied, a cue only returns above this error.
    ///
    /// Strictly larger than the enter tolerance: without the gap, a cue oscillates on
    /// and off at the boundary and the overlay strobes.
    public var positionExitTolerance: Double

    /// Subject-size error, as a fraction of the target height, below which size is fine.
    public var sizeEnterTolerance: Double
    public var sizeExitTolerance: Double

    /// Roll error below this is treated as level.
    public var rollEnterTolerance: Angle
    public var rollExitTolerance: Angle

    /// Camera-height error, as a fraction of subject height, below which height is fine.
    public var heightEnterTolerance: Double
    public var heightExitTolerance: Double

    /// Subject body-yaw error below this is treated as correct.
    public var bodyYawEnterTolerance: Angle
    public var bodyYawExitTolerance: Angle

    // MARK: Cue budget

    /// Most cues shown at once. A human cannot act on five simultaneous corrections;
    /// when many things are wrong, showing only the most important one is the feature.
    public var maximumCues: Int
    /// Most cues per actor.
    public var maximumCuesPerActor: Int

    // MARK: Relative magnitude thresholds

    /// Error, relative to its tolerance, above which a cue reads as "moderate".
    public var moderateErrorMultiple: Double
    /// Error, relative to its tolerance, above which a cue reads as "large".
    public var largeErrorMultiple: Double

    // MARK: Trust

    /// Confidence a metric measurement needs before a cue may carry units.
    public var minimumMetricConfidence: Double
    /// Confidence a detection needs before it drives guidance at all.
    public var minimumDetectionConfidence: Double

    // MARK: Priorities

    //
    // Fix what changes the plan's validity first: gross placement, then distance,
    // then height, then levelling, then pose refinement.

    public var subjectPlacementPriority: Int
    public var cameraDistancePriority: Int
    public var cameraHeightPriority: Int
    public var levellingPriority: Int
    public var poseRefinementPriority: Int
    public var focalLengthPriority: Int

    public init(
        positionEnterTolerance: Double = 0.03,
        positionExitTolerance: Double = 0.048,
        sizeEnterTolerance: Double = 0.08,
        sizeExitTolerance: Double = 0.128,
        rollEnterTolerance: Angle = .degrees(1.0),
        rollExitTolerance: Angle = .degrees(1.6),
        heightEnterTolerance: Double = 0.05,
        heightExitTolerance: Double = 0.08,
        bodyYawEnterTolerance: Angle = .degrees(8),
        bodyYawExitTolerance: Angle = .degrees(12.8),
        maximumCues: Int = 3,
        maximumCuesPerActor: Int = 1,
        moderateErrorMultiple: Double = 2.5,
        largeErrorMultiple: Double = 6,
        minimumMetricConfidence: Double = 0.6,
        minimumDetectionConfidence: Double = 0.3,
        subjectPlacementPriority: Int = 100,
        cameraDistancePriority: Int = 90,
        cameraHeightPriority: Int = 80,
        levellingPriority: Int = 70,
        poseRefinementPriority: Int = 50,
        focalLengthPriority: Int = 40
    ) {
        self.positionEnterTolerance = positionEnterTolerance
        self.positionExitTolerance = positionExitTolerance
        self.sizeEnterTolerance = sizeEnterTolerance
        self.sizeExitTolerance = sizeExitTolerance
        self.rollEnterTolerance = rollEnterTolerance
        self.rollExitTolerance = rollExitTolerance
        self.heightEnterTolerance = heightEnterTolerance
        self.heightExitTolerance = heightExitTolerance
        self.bodyYawEnterTolerance = bodyYawEnterTolerance
        self.bodyYawExitTolerance = bodyYawExitTolerance
        self.maximumCues = maximumCues
        self.maximumCuesPerActor = maximumCuesPerActor
        self.moderateErrorMultiple = moderateErrorMultiple
        self.largeErrorMultiple = largeErrorMultiple
        self.minimumMetricConfidence = minimumMetricConfidence
        self.minimumDetectionConfidence = minimumDetectionConfidence
        self.subjectPlacementPriority = subjectPlacementPriority
        self.cameraDistancePriority = cameraDistancePriority
        self.cameraHeightPriority = cameraHeightPriority
        self.levellingPriority = levellingPriority
        self.poseRefinementPriority = poseRefinementPriority
        self.focalLengthPriority = focalLengthPriority
    }

    public static let `default` = GuidancePolicy()

    /// Whether the enter/exit pairs actually form a hysteresis band.
    ///
    /// Asserted in tests: an exit tolerance at or below its enter tolerance silently
    /// removes the hysteresis and reintroduces flicker.
    public var hasValidHysteresis: Bool {
        positionExitTolerance > positionEnterTolerance
            && sizeExitTolerance > sizeEnterTolerance
            && rollExitTolerance > rollEnterTolerance
            && heightExitTolerance > heightEnterTolerance
            && bodyYawExitTolerance > bodyYawEnterTolerance
    }
}
