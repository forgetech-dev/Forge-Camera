import ForgeTestSupport
import Testing
@testable import ForgeCore

@Suite("Exposure engine")
struct ExposureEngineTests {
    let engine = ExposureEngine()

    /// A mirrorless-like body: everything reported and writable.
    let fullControl = ExposureCapabilities(
        iso: .init(supportedRange: 100 ... 25600, isWritable: true),
        shutterDenominator: .init(supportedRange: 1 ... 8000, isWritable: true),
        aperture: .init(supportedRange: 1.4 ... 22, isWritable: true)
    )

    // MARK: Capability gating

    @Test("A camera that reports nothing yields no values rather than invented ones")
    func noCapabilitiesYieldsNoSettings() {
        let recommendation = engine.recommendation(
            for: SceneFixtures.scene(),
            intent: ExposurePlan(priority: .subject),
            capabilities: .none
        )

        #expect(recommendation.settings == .empty)
        #expect(recommendation.manualRequests.isEmpty)
    }

    @Test("Values that cannot be written become manual requests, not silent failures")
    func unwritableParametersBecomeManualRequests() {
        let recommendation = engine.recommendation(
            for: SceneFixtures.scene(camera: SceneFixtures.cameraWithKnownOptics()),
            intent: ExposurePlan(priority: .subject),
            capabilities: .automatic
        )

        // The user has to turn a dial themselves; the app must say so.
        #expect(recommendation.manualRequests.contains(.iso))
        #expect(recommendation.manualRequests.contains(.shutter))
        #expect(recommendation.manualRequests.contains(.aperture))
    }

    @Test("A parameter the camera never reports is left absent")
    func unreportedParameterIsAbsent() {
        let isoOnly = ExposureCapabilities(
            iso: .init(supportedRange: 100 ... 6400, isWritable: true)
        )

        let recommendation = engine.recommendation(
            for: SceneFixtures.scene(),
            intent: nil,
            capabilities: isoOnly
        )

        #expect(recommendation.settings.iso != nil)
        // Absent is not zero.
        #expect(recommendation.settings.aperture == nil)
        #expect(recommendation.settings.shutterDenominator == nil)
    }

    // MARK: Shutter floor

    @Test("The reciprocal rule sets the shutter floor from focal length")
    func reciprocalRuleAppliesToShutter() {
        let scene = SceneFixtures.scene(camera: CameraState(focalLength: 85))

        let recommendation = engine.recommendation(
            for: scene,
            intent: nil,
            capabilities: fullControl
        )

        // 85mm × safety factor 2 = 1/170s.
        #expect(recommendation.settings.shutterDenominator == 170)
    }

    @Test("An unknown focal length falls back rather than guessing a floor")
    func unknownFocalLengthUsesFallback() {
        let recommendation = engine.recommendation(
            for: SceneFixtures.scene(camera: CameraState(focalLength: nil)),
            intent: nil,
            capabilities: fullControl
        )

        #expect(recommendation.settings.shutterDenominator == 60)
    }

    @Test("The plan can demand a faster shutter but never a slower one")
    func planRaisesShutterFloorOnly() {
        let scene = SceneFixtures.scene(camera: CameraState(focalLength: 35))

        let faster = engine.recommendation(
            for: scene,
            intent: ExposurePlan(minShutterDenominator: 500),
            capabilities: fullControl
        )
        #expect(faster.settings.shutterDenominator == 500)

        let slower = engine.recommendation(
            for: scene,
            intent: ExposurePlan(minShutterDenominator: 30),
            capabilities: fullControl
        )
        // A correctly exposed blurred frame is still a failed photograph, so the
        // handheld floor of 70 wins.
        #expect(slower.settings.shutterDenominator == 70)
    }

    @Test("Motion priority forces a shutter fast enough to freeze movement")
    func motionPriorityFreezesMovement() {
        let recommendation = engine.recommendation(
            for: SceneFixtures.scene(camera: CameraState(focalLength: 35)),
            intent: ExposurePlan(priority: .motion),
            capabilities: fullControl
        )

        #expect(recommendation.settings.shutterDenominator == 250)
    }

    @Test("A shutter beyond the camera's range is clamped and reported")
    func shutterIsClampedToCapability() {
        let slowCamera = ExposureCapabilities(
            shutterDenominator: .init(supportedRange: 1 ... 200, isWritable: true)
        )

        let recommendation = engine.recommendation(
            for: SceneFixtures.scene(camera: CameraState(focalLength: 35)),
            intent: ExposurePlan(priority: .motion),
            capabilities: slowCamera
        )

        #expect(recommendation.settings.shutterDenominator == 200)
        #expect(recommendation.clamped.contains(.shutter))
    }

    // MARK: Aperture

    @Test("The plan's aperture hint is honoured when the lens allows it")
    func apertureHintIsHonoured() {
        let recommendation = engine.recommendation(
            for: SceneFixtures.scene(),
            intent: ExposurePlan(priority: .subject, apertureHint: 2.0),
            capabilities: fullControl
        )

        #expect(recommendation.settings.aperture == 2.0)
    }

    @Test("An aperture the lens cannot reach is clamped and reported")
    func apertureIsClampedToLens() {
        let recommendation = engine.recommendation(
            for: SceneFixtures.scene(),
            intent: ExposurePlan(apertureHint: 1.0),
            capabilities: fullControl
        )

        #expect(recommendation.settings.aperture == 1.4)
        #expect(recommendation.clamped.contains(.aperture))
    }

    @Test("Depth priority stops down where subject priority opens up")
    func priorityChangesDefaultAperture() {
        let scene = SceneFixtures.scene()

        let depth = engine.recommendation(
            for: scene,
            intent: ExposurePlan(priority: .depth),
            capabilities: fullControl
        )
        let subject = engine.recommendation(
            for: scene,
            intent: ExposurePlan(priority: .subject),
            capabilities: fullControl
        )

        #expect(depth.settings.aperture == 8)
        #expect(subject.settings.aperture == 2.8)
    }

    // MARK: Priority inference

    @Test("Clipped highlights take priority when the director expressed none")
    func clippedHighlightsInferPriority() {
        let blown = SceneFixtures.scene(
            lighting: LightingEstimate(
                meanLuma: 0.8,
                clippedHighlightFraction: 0.2,
                clippedShadowFraction: 0
            ),
            camera: CameraState(focalLength: 35, iso: 800)
        )
        let even = SceneFixtures.scene(
            lighting: LightingEstimate(
                meanLuma: 0.5,
                clippedHighlightFraction: 0,
                clippedShadowFraction: 0
            ),
            camera: CameraState(focalLength: 35, iso: 800)
        )

        let protected = engine.recommendation(for: blown, intent: nil, capabilities: fullControl)
        let normal = engine.recommendation(for: even, intent: nil, capabilities: fullControl)

        // Blown highlights are unrecoverable, so exposure is pulled down a stop.
        #expect(protected.settings.iso == 400)
        #expect(normal.settings.iso == 800)
    }

    @Test("An explicit director priority overrides what the scene suggests")
    func explicitPriorityWins() {
        let blown = SceneFixtures.scene(
            lighting: LightingEstimate(
                meanLuma: 0.8,
                clippedHighlightFraction: 0.2,
                clippedShadowFraction: 0
            ),
            camera: CameraState(focalLength: 35, iso: 800)
        )

        let recommendation = engine.recommendation(
            for: blown,
            intent: ExposurePlan(priority: .subject),
            capabilities: fullControl
        )

        #expect(recommendation.settings.iso == 800)
    }

    // MARK: ISO

    @Test("ISO is held under the preferred ceiling")
    func isoRespectsPreferredCeiling() {
        let scene = SceneFixtures.scene(camera: CameraState(focalLength: 35, iso: 12800))

        let recommendation = engine.recommendation(
            for: scene,
            intent: ExposurePlan(priority: .subject),
            capabilities: fullControl
        )

        #expect(recommendation.settings.iso == 3200)
    }

    @Test("ISO below the camera's floor is clamped and reported")
    func isoIsClampedToCapability() {
        let scene = SceneFixtures.scene(camera: CameraState(focalLength: 35, iso: 50))
        let highFloor = ExposureCapabilities(
            iso: .init(supportedRange: 200 ... 6400, isWritable: true)
        )

        let recommendation = engine.recommendation(
            for: scene,
            intent: nil,
            capabilities: highFloor
        )

        #expect(recommendation.settings.iso == 200)
        #expect(recommendation.clamped.contains(.iso))
    }

    // MARK: Forward-compatible enum comparison

    @Test("An unrecognised priority falls back to inference instead of being obeyed")
    func unknownPriorityFallsBackToInference() {
        let blown = SceneFixtures.scene(
            lighting: LightingEstimate(
                meanLuma: 0.8,
                clippedHighlightFraction: 0.2,
                clippedShadowFraction: 0
            ),
            camera: CameraState(focalLength: 35, iso: 800)
        )

        let recommendation = engine.recommendation(
            for: blown,
            intent: ExposurePlan(priority: ExposurePriority(rawValue: "vibes")),
            capabilities: fullControl
        )

        // The engine cannot act on a priority it does not understand, so it infers
        // from the scene: blown highlights, therefore pull exposure down a stop.
        #expect(recommendation.settings.iso == 400)
    }

    @Test("RawRepresentable derives == from rawValue, so unknown must be pattern matched")
    func rawRepresentableEqualityIsRawValueBased() {
        // This is a real trap: `.depth == .unknown("depth")` is TRUE, which makes
        // `value != .unknown(value.rawValue)` always false and silently useless.
        #expect(ExposurePriority.depth == ExposurePriority.unknown("depth"))
        #expect(ExposurePriority.depth.isKnown)
        #expect(!ExposurePriority.unknown("vibes").isKnown)
    }

    // MARK: Determinism

    @Test("The same inputs always produce the same recommendation")
    func isDeterministic() {
        let scene = SceneFixtures.scene(camera: SceneFixtures.cameraWithKnownOptics())
        let intent = ExposurePlan(priority: .subject, apertureHint: 2.8, minShutterDenominator: 250)

        let first = engine.recommendation(for: scene, intent: intent, capabilities: fullControl)
        let second = engine.recommendation(for: scene, intent: intent, capabilities: fullControl)

        #expect(first == second)
    }
}
