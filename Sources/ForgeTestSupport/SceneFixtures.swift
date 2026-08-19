import ForgeCore

/// Deterministic scene and plan builders for tests.
///
/// Fixtures are deliberately **asymmetric** where geometry is involved: a centred
/// square passes a broken vertical flip, so symmetric test data hides exactly the bug
/// these fixtures exist to catch.
public enum SceneFixtures {
    public static let landscapeFrame = FrameGeometry(
        pixelWidth: 1920,
        pixelHeight: 1080,
        appliedRotation: .zero,
        wasMirrored: false
    )

    public static let portraitFrame = FrameGeometry(
        pixelWidth: 1080,
        pixelHeight: 1920,
        appliedRotation: .degrees(90),
        wasMirrored: false
    )

    /// A subject that is off-centre and not square, so placement and size errors are
    /// distinguishable and a flipped axis is visible.
    public static func subject(
        id: String = "subject-1",
        bounds: NormalizedRect = NormalizedRect(x: 0.2, y: 0.3, width: 0.15, height: 0.4),
        faceYaw: Angle? = nil,
        faceConfidence: Double = 0.9,
        distance: Measured<Double>? = nil,
        salience: Double = 1
    ) -> DetectedSubject {
        DetectedSubject(
            id: SubjectID(id),
            bounds: bounds,
            kind: .person,
            pose: nil,
            faceOrientation: faceYaw.map {
                FaceOrientation(yaw: $0, pitch: .zero, roll: .zero, confidence: faceConfidence)
            },
            distance: distance,
            salience: salience
        )
    }

    public static func scene(
        timestamp: Double = 0,
        frame: FrameGeometry = landscapeFrame,
        subjects: [DetectedSubject] = [subject()],
        horizon: HorizonEstimate? = nil,
        lighting: LightingEstimate? = nil,
        motion: DeviceMotionState? = nil,
        camera: CameraState? = nil
    ) -> SceneState {
        SceneState(
            timestamp: timestamp,
            frame: frame,
            subjects: subjects,
            horizon: horizon,
            lighting: lighting,
            motion: motion,
            camera: camera
        )
    }

    /// A camera state with a known field of view, so angular guidance is available.
    public static func cameraWithKnownOptics(focalLength: Double = 35) -> CameraState {
        CameraState(
            focalLength: focalLength,
            fieldOfView: FieldOfView(horizontal: .degrees(54), aspectRatio: 16.0 / 9.0),
            aperture: 2.8,
            iso: 400,
            shutterDenominator: 250
        )
    }

    /// A metrically trustworthy subject distance.
    public static func trustedDistance(
        _ meters: Double,
        confidence: Double = 0.9
    ) -> Measured<Double> {
        Measured(value: meters, confidence: confidence, provenance: .lidar)
    }

    /// A distance inferred from image cues alone. Never metric, whatever its confidence.
    public static func estimatedDistance(
        _ meters: Double,
        confidence: Double = 0.95
    ) -> Measured<Double> {
        Measured(value: meters, confidence: confidence, provenance: .estimated)
    }

    /// Motion with the frame source and motion source rigidly coupled.
    public static func rigidMotion(roll: Angle = .zero) -> DeviceMotionState {
        DeviceMotionState(roll: roll, pitch: .zero, position: nil, coupling: .rigid)
    }

    /// Motion where the phone is not attached to the camera taking the picture.
    public static func decoupledMotion(roll: Angle = .zero) -> DeviceMotionState {
        DeviceMotionState(roll: roll, pitch: .zero, position: nil, coupling: .decoupled)
    }
}

/// Plan builders covering the shapes the validator must survive.
public enum PlanFixtures {
    public static func valid(
        planId: String = "plan-1",
        intent: PhotographicIntent = .portrait,
        selection: SubjectSelection? = nil,
        framing: FramingPlan? = nil,
        displayAdvice: [String]? = nil,
        subject: SubjectPlan? = SubjectPlan(targetX: 0.66, targetY: 0.45, targetHeight: 0.6),
        scene: ScenePlan? = nil,
        camera: CameraPlan? = nil,
        exposure: ExposurePlan? = nil,
        capture: CapturePlan? = nil
    ) -> CompositionPlan {
        CompositionPlan(
            planId: planId,
            requestId: "request-1",
            intent: intent,
            confidence: 0.8,
            rationale: "Fixture plan.",
            selection: selection,
            framing: framing,
            displayAdvice: displayAdvice,
            subject: subject,
            scene: scene,
            camera: camera,
            exposure: exposure,
            capture: capture,
            expiresAfterSeconds: 20
        )
    }

    /// A plan where the director expressed no opinion at all.
    ///
    /// Must survive validation and produce no cues — "absent" is not "zero".
    public static let empty = CompositionPlan(
        planId: "plan-empty",
        intent: .portrait
    )
}

/// A director that returns whatever it was given, so tests control the plan exactly.
public struct MockDirectorProvider: DirectorProvider {
    public enum Behavior: Sendable {
        case returns(CompositionPlan)
        case fails(DirectorError)
    }

    private let behavior: Behavior

    public init(_ behavior: Behavior) {
        self.behavior = behavior
    }

    public init(returning plan: CompositionPlan) {
        behavior = .returns(plan)
    }

    public func plan(_ request: DirectorRequest) async throws -> CompositionPlan {
        switch behavior {
        case let .returns(plan): plan
        case let .fails(error): throw error
        }
    }
}
