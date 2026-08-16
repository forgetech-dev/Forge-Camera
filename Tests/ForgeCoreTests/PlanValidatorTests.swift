import ForgeTestSupport
import Foundation
import Testing
@testable import ForgeCore

@Suite("Plan validation")
struct PlanValidatorTests {
    let validator = PlanValidator()

    // MARK: Hard rejections

    @Test("A plan from an unsupported schema version is rejected outright")
    func rejectsWrongSchemaVersion() {
        let plan = CompositionPlan(schemaVersion: 99, planId: "p", intent: .portrait)
        #expect(throws: PlanValidator.Failure.self) {
            try validator.validate(plan)
        }
    }

    @Test("A plan without an identity is rejected outright")
    func rejectsEmptyPlanId() {
        #expect(throws: PlanValidator.Failure.missingPlanId) {
            try validator.validate(CompositionPlan(planId: "   ", intent: .portrait))
        }
    }

    @Test("An unrecognised intent is rejected because engines cannot act on it")
    func rejectsUnknownIntent() {
        let plan = CompositionPlan(
            planId: "p",
            intent: PhotographicIntent(rawValue: "interpretive_dance")
        )
        #expect(throws: PlanValidator.Failure.self) {
            try validator.validate(plan)
        }
    }

    // MARK: Field-level degradation

    @Test("One bad field is dropped without losing the rest of the plan")
    func badFieldDoesNotDiscardWholePlan() throws {
        let plan = PlanFixtures.valid(
            subject: SubjectPlan(targetX: 0.66, targetY: 0.45, targetHeight: 0.6),
            camera: CameraPlan(recommendedFocalLength: -12)
        )

        let result = try validator.validate(plan)

        // The silly focal length is gone.
        #expect(result.plan.camera?.recommendedFocalLength == nil)
        // The good subject placement survives, which is the whole point.
        #expect(result.plan.subject?.targetX == 0.66)
        #expect(result.plan.subject?.targetHeight == 0.6)
        #expect(!result.warnings.isEmpty)
    }

    @Test("Out-of-range normalized values are clamped and reported")
    func clampsNormalizedValues() throws {
        let plan = PlanFixtures.valid(subject: SubjectPlan(
            targetX: 1.8,
            targetY: -0.4,
            targetHeight: 0.5
        ))

        let result = try validator.validate(plan)

        #expect(result.plan.subject?.targetX == 1)
        #expect(result.plan.subject?.targetY == 0)
        #expect(result.warnings.contains { $0.field == "subject.targetX" })
        #expect(result.warnings.contains { $0.field == "subject.targetY" })
    }

    @Test("Non-finite values are dropped, never propagated")
    func dropsNonFiniteValues() throws {
        let plan = PlanFixtures.valid(
            subject: SubjectPlan(targetX: .nan, targetY: .infinity, targetHeight: 0.5)
        )

        let result = try validator.validate(plan)

        // A NaN reaching the guidance engine poisons everything downstream silently.
        #expect(result.plan.subject?.targetX == nil)
        #expect(result.plan.subject?.targetY == nil)
        #expect(result.plan.subject?.targetHeight == 0.5)
    }

    @Test("Angles are wrapped into the shortest rotation")
    func wrapsAngles() throws {
        let plan = PlanFixtures.valid(
            subject: SubjectPlan(targetX: 0.5, bodyYaw: .degrees(350))
        )

        let result = try validator.validate(plan)

        #expect(result.plan.subject?.bodyYaw == .degrees(-10))
        #expect(result.warnings.contains { $0.field == "subject.bodyYaw" })
    }

    @Test("A section whose every field was dropped becomes absent, not empty")
    func fullyInvalidSectionBecomesNil() throws {
        let plan = PlanFixtures.valid(
            subject: nil,
            camera: CameraPlan(
                heightAdjustment: .nan,
                yawAdjustment: nil,
                recommendedFocalLength: -1
            )
        )

        let result = try validator.validate(plan)

        // Downstream code should never have to distinguish "present but useless"
        // from "absent".
        #expect(result.plan.camera == nil)
    }

    // MARK: Absent is not zero

    @Test("A plan with no opinions survives validation intact")
    func emptyPlanSurvives() throws {
        let result = try validator.validate(PlanFixtures.empty)

        #expect(result.isClean)
        #expect(result.plan.subject == nil)
        #expect(result.plan.camera == nil)
        #expect(result.plan.scene == nil)
    }

    @Test("An explicit zero is preserved and never confused with an absent field")
    func explicitZeroIsPreserved() throws {
        let plan = PlanFixtures.valid(camera: CameraPlan(heightAdjustment: 0))

        let result = try validator.validate(plan)

        // "Hold this height" and "no opinion about height" are different instructions.
        #expect(result.plan.camera?.heightAdjustment == 0)
        #expect(result.plan.camera?.heightAdjustment != nil)
    }

    // MARK: Focal length

    @Test("A focal length is snapped to what the camera can actually deliver")
    func snapsFocalLengthToSupportedRange() throws {
        let plan = PlanFixtures.valid(camera: CameraPlan(recommendedFocalLength: 200))
        let context = PlanValidator.Context(supportedFocalLengths: 35 ... 85)

        let result = try validator.validate(plan, context: context)

        #expect(result.plan.camera?.recommendedFocalLength == 85)
        #expect(result.warnings.contains { $0.field == "camera.recommendedFocalLength" })
    }

    @Test("A focal length is dropped when the camera's range is unknown")
    func dropsFocalLengthWhenRangeUnknown() throws {
        let plan = PlanFixtures.valid(camera: CameraPlan(recommendedFocalLength: 50))

        let result = try validator.validate(plan, context: .unconstrained)

        #expect(result.plan.camera?.recommendedFocalLength == nil)
    }

    // MARK: Avoid regions

    @Test("A region covering most of the frame is rejected as unactionable")
    func rejectsOversizedAvoidRegion() throws {
        let plan = PlanFixtures.valid(
            scene: ScenePlan(avoidRegions: [NormalizedRect(x: 0, y: 0, width: 1, height: 0.95)])
        )

        let result = try validator.validate(plan)

        // "Avoid everything" is a director failure; acting on it produces nonsense.
        #expect(result.plan.scene?.avoidRegions == nil)
        #expect(result.warnings.contains { $0.field == "scene.avoidRegions" })
    }

    @Test("A usable region is kept while an unusable one beside it is dropped")
    func keepsGoodRegionsDropsBad() throws {
        let good = NormalizedRect(x: 0, y: 0, width: 0.2, height: 0.3)
        let outside = NormalizedRect(x: 0.9, y: 0.9, width: 0.5, height: 0.5)
        let plan = PlanFixtures.valid(scene: ScenePlan(avoidRegions: [good, outside]))

        let result = try validator.validate(plan)

        #expect(result.plan.scene?.avoidRegions == [good])
    }

    // MARK: Capture

    @Test("A bracket without usable stops degrades to a single shot")
    func bracketWithoutStopsBecomesSingle() throws {
        let plan = PlanFixtures.valid(capture: CapturePlan(kind: .bracket, stops: nil))

        let result = try validator.validate(plan)

        #expect(result.plan.capture?.kind == .single)
        #expect(result.warnings.contains { $0.field == "capture.stops" })
    }

    @Test("Bracket stops are sorted so downstream ordering is deterministic")
    func bracketStopsSorted() throws {
        let plan = PlanFixtures.valid(capture: CapturePlan(kind: .bracket, stops: [2, -2, 0]))

        let result = try validator.validate(plan)

        #expect(result.plan.capture?.stops == [-2, 0, 2])
    }

    // MARK: Forward compatibility

    @Test("Unknown enum values inside a known plan are preserved, not fatal")
    func unknownPoseHintSurvives() throws {
        let plan = PlanFixtures.valid(
            subject: SubjectPlan(targetX: 0.5, poseHint: PoseHint(rawValue: "levitate"))
        )

        let result = try validator.validate(plan)

        // Engines ignore unknown hints; a director can add one without a schema bump.
        #expect(result.plan.subject?.poseHint == PoseHint(rawValue: "levitate"))
    }

    @Test("Unknown top-level keys in JSON are ignored rather than failing the decode")
    func unknownJSONKeysIgnored() throws {
        let json = Data("""
        {
          "schemaVersion": 1,
          "planId": "plan-1",
          "intent": "portrait",
          "subject": { "targetX": 0.66, "targetHeight": 0.6 },
          "somethingTheDirectorInvented": { "nested": true }
        }
        """.utf8)

        let decoded = try JSONDecoder().decode(CompositionPlan.self, from: json)
        let result = try validator.validate(decoded)

        #expect(result.plan.subject?.targetX == 0.66)
    }

    @Test("Angles and regions use the compact wire shapes a model produces reliably")
    func wireShapes() throws {
        let json = Data("""
        {
          "schemaVersion": 1,
          "planId": "plan-1",
          "intent": "environmental_portrait",
          "subject": { "bodyYaw": -20 },
          "scene": { "avoidRegions": [[0.0, 0.0, 0.2, 0.4]] }
        }
        """.utf8)

        let decoded = try JSONDecoder().decode(CompositionPlan.self, from: json)

        #expect(decoded.subject?.bodyYaw == .degrees(-20))
        #expect(decoded.scene?.avoidRegions?.first == NormalizedRect(
            x: 0,
            y: 0,
            width: 0.2,
            height: 0.4
        ))
    }

    @Test("A plan survives an encode and decode round trip")
    func codableRoundTrip() throws {
        let original = PlanFixtures.valid(
            scene: ScenePlan(
                targetHorizon: 0.34,
                avoidRegions: [.init(x: 0, y: 0, width: 0.2, height: 0.4)]
            ),
            camera: CameraPlan(heightAdjustment: -0.15, yawAdjustment: .degrees(7)),
            capture: CapturePlan(kind: .bracket, stops: [-2, 0, 2])
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CompositionPlan.self, from: data)

        #expect(decoded == original)
    }
}
