import ForgeTestSupport
import Testing
@testable import ForgeCore

@Suite("Guidance engine")
struct GuidanceEngineTests {
    let engine = GuidanceEngine()

    // MARK: No plan

    @Test("With no plan latched the engine says nothing rather than guessing")
    func noPlanProducesIdleGuidance() {
        let output = engine.guidance(for: SceneFixtures.scene(), plan: nil)

        #expect(output.guidance.cues.isEmpty)
        #expect(output.guidance.planId == nil)
    }

    @Test("A plan with no opinions produces no cues")
    func emptyPlanProducesNoCues() {
        let output = engine.guidance(for: SceneFixtures.scene(), plan: PlanFixtures.empty)

        // Absent is not zero: no opinion must not become "hold position".
        #expect(output.guidance.cues.isEmpty)
        #expect(output.guidance.readiness == .ready)
    }

    // MARK: Deadband and hysteresis

    @Test("An error inside the deadband produces no cue")
    func errorInsideDeadbandIsSilent() {
        // Subject centre is at x = 0.275; target sits within the enter tolerance.
        let scene = SceneFixtures.scene()
        let plan = PlanFixtures.valid(subject: SubjectPlan(targetX: 0.28))

        let output = engine.guidance(for: scene, plan: plan)

        #expect(output.guidance.cue(for: .photographer) == nil)
    }

    @Test("A silent axis must clear the wider exit tolerance before it speaks")
    func silentAxisNeedsExitTolerance() {
        let policy = GuidancePolicy.default
        let scene = SceneFixtures.scene()
        // An error between the two tolerances: enough to keep an active cue alive,
        // not enough to start a new one.
        let betweenTolerances = (policy.positionEnterTolerance + policy.positionExitTolerance) / 2
        let plan = PlanFixtures.valid(subject: SubjectPlan(targetX: 0.275 + betweenTolerances))

        let fromSilence = engine.guidance(for: scene, plan: plan, memory: .initial)

        #expect(fromSilence.guidance.cue(for: .photographer) == nil)
    }

    @Test("An already-active axis keeps speaking down to the narrower enter tolerance")
    func activeAxisPersistsInsideHysteresisBand() {
        let policy = GuidancePolicy.default
        let scene = SceneFixtures.scene()
        let betweenTolerances = (policy.positionEnterTolerance + policy.positionExitTolerance) / 2
        let plan = PlanFixtures.valid(subject: SubjectPlan(targetX: 0.275 + betweenTolerances))

        let alreadyActive = GuidanceEngine.MemoryState(activeAxes: [.panRight])
        let output = engine.guidance(for: scene, plan: plan, memory: alreadyActive)

        // Same scene, same plan, different history — this asymmetry is the hysteresis.
        #expect(output.guidance.cue(for: .photographer)?.axis == .panRight)
    }

    @Test("A cue does not oscillate while the error hovers in the hysteresis band")
    func noOscillationInBand() {
        let policy = GuidancePolicy.default
        let scene = SceneFixtures.scene()
        let betweenTolerances = (policy.positionEnterTolerance + policy.positionExitTolerance) / 2
        let plan = PlanFixtures.valid(subject: SubjectPlan(targetX: 0.275 + betweenTolerances))

        // Feed the same borderline frame repeatedly and confirm the answer is stable.
        var memory = GuidanceEngine.MemoryState(activeAxes: [.panRight])
        var results: [Bool] = []
        for _ in 0 ..< 10 {
            let output = engine.guidance(for: scene, plan: plan, memory: memory)
            results.append(output.guidance.cue(for: .photographer) != nil)
            memory = output.memory
        }

        #expect(results.allSatisfy { $0 == true })
    }

    @Test("Clearly exceeding the tolerance produces a cue from silence")
    func largeErrorProducesCue() {
        let scene = SceneFixtures.scene()
        let plan = PlanFixtures.valid(subject: SubjectPlan(targetX: 0.8))

        let output = engine.guidance(for: scene, plan: plan)

        let cue = output.guidance.cue(for: .photographer)
        #expect(cue?.axis == .panRight)
    }

    @Test("Placement error is corrected by rotating, not by stepping sideways")
    func placementUsesRotationNotTranslation() {
        let scene = SceneFixtures.scene()
        let plan = PlanFixtures.valid(subject: SubjectPlan(targetX: 0.8))

        let cue = engine.guidance(for: scene, plan: plan).guidance.cue(for: .photographer)

        // Rotation is the cheapest correction and preserves perspective; lateral
        // movement is reserved for background conflicts.
        #expect(cue?.axis == .panRight)
        #expect(cue?.axis != .right)
    }

    // MARK: Honesty about precision

    @Test("A trusted metric distance lets a dolly cue carry units")
    func trustedDistanceProducesMetricCue() {
        let subject = SceneFixtures.subject(
            bounds: NormalizedRect(x: 0.4, y: 0.3, width: 0.1, height: 0.3),
            distance: SceneFixtures.trustedDistance(3.0)
        )
        let scene = SceneFixtures.scene(subjects: [subject])
        let plan = PlanFixtures.valid(subject: SubjectPlan(targetHeight: 0.6))

        let output = engine.guidance(for: scene, plan: plan)
        let cue = output.guidance.cues.first { $0.axis == .forward || $0.axis == .backward }

        #expect(cue?.magnitude.isMetric == true)
        // d_target = d_current * (s_current / s_target) = 3.0 * (0.3 / 0.6) = 1.5
        if case let .metric(meters, _) = cue?.magnitude {
            #expect(abs(meters - 1.5) < 1e-9)
        } else {
            Issue.record("expected a metric magnitude")
        }
    }

    @Test("A confident estimate never becomes a metric cue")
    func estimatedDistanceStaysRelative() {
        let subject = SceneFixtures.subject(
            bounds: NormalizedRect(x: 0.4, y: 0.3, width: 0.1, height: 0.3),
            distance: SceneFixtures.estimatedDistance(3.0, confidence: 0.99)
        )
        let scene = SceneFixtures.scene(subjects: [subject])
        let plan = PlanFixtures.valid(subject: SubjectPlan(targetHeight: 0.6))

        let output = engine.guidance(for: scene, plan: plan)
        let cue = output.guidance.cues.first { $0.axis == .forward || $0.axis == .backward }

        // The value is confident but inferred from image cues alone, so it may inform
        // relative magnitude and must never print a number.
        #expect(cue != nil)
        #expect(cue?.magnitude.isMetric == false)
    }

    @Test("No distance at all still produces a usable relative dolly cue")
    func noDistanceStillGuides() {
        let subject = SceneFixtures.subject(
            bounds: NormalizedRect(x: 0.4, y: 0.3, width: 0.1, height: 0.3),
            distance: nil
        )
        let scene = SceneFixtures.scene(subjects: [subject])
        let plan = PlanFixtures.valid(subject: SubjectPlan(targetHeight: 0.6))

        let cue = engine.guidance(for: scene, plan: plan).guidance.cues
            .first { $0.axis == .forward || $0.axis == .backward }

        // The subject's real height cancels out of the ratio, so direction and
        // relative size are knowable with no metric input whatsoever.
        #expect(cue?.axis == .forward)
        #expect(cue?.magnitude.isMetric == false)
    }

    @Test("Camera height cues stay relative because the plan's unit is dimensionless")
    func heightCueIsRelative() {
        let scene = SceneFixtures.scene()
        let plan = PlanFixtures.valid(subject: nil, camera: CameraPlan(heightAdjustment: -0.4))

        let cue = engine.guidance(for: scene, plan: plan).guidance.cue(for: .camera)

        #expect(cue?.axis == .down)
        #expect(cue?.magnitude.isMetric == false)
    }

    @Test("Angular guidance is exact when the field of view is known")
    func knownFieldOfViewGivesExactRotation() {
        let scene = SceneFixtures.scene(camera: SceneFixtures.cameraWithKnownOptics())
        let plan = PlanFixtures.valid(subject: SubjectPlan(targetX: 0.8))

        let cue = engine.guidance(for: scene, plan: plan).guidance.cue(for: .photographer)

        guard case let .degrees(angle, confidence)? = cue?.rotation else {
            Issue.record("expected an exact angular rotation")
            return
        }
        #expect(confidence == 1)
        #expect(angle.degrees > 0)
    }

    @Test("Without a field of view the rotation degrades instead of inventing an angle")
    func unknownFieldOfViewDegradesRotation() {
        let scene = SceneFixtures.scene(camera: CameraState(focalLength: nil, fieldOfView: nil))
        let plan = PlanFixtures.valid(subject: SubjectPlan(targetX: 0.8))

        let cue = engine.guidance(for: scene, plan: plan).guidance.cue(for: .photographer)

        guard case .relative? = cue?.rotation else {
            Issue.record("expected a relative rotation when optics are unknown")
            return
        }
    }

    // MARK: Cue budget

    @Test("At most one cue per actor survives ranking")
    func atMostOneCuePerActor() {
        // Everything is wrong at once.
        let subject = SceneFixtures.subject(
            bounds: NormalizedRect(x: 0.05, y: 0.05, width: 0.1, height: 0.2),
            faceYaw: .degrees(60)
        )
        let scene = SceneFixtures.scene(
            subjects: [subject],
            horizon: HorizonEstimate(normalizedY: 0.5, roll: .degrees(9), confidence: 0.9)
        )
        let plan = PlanFixtures.valid(
            subject: SubjectPlan(
                targetX: 0.9,
                targetY: 0.9,
                targetHeight: 0.8,
                bodyYaw: .degrees(-30)
            ),
            camera: CameraPlan(heightAdjustment: -0.5)
        )

        let cues = engine.guidance(for: scene, plan: plan).guidance.cues

        for actor in GuidanceActor.allCases {
            #expect(cues.filter { $0.actor == actor }.count <= 1)
        }
    }

    @Test("The total cue budget is never exceeded")
    func respectsTotalCueBudget() {
        let subject = SceneFixtures.subject(
            bounds: NormalizedRect(x: 0.05, y: 0.05, width: 0.1, height: 0.2),
            faceYaw: .degrees(60)
        )
        let scene = SceneFixtures.scene(
            subjects: [subject],
            horizon: HorizonEstimate(normalizedY: 0.5, roll: .degrees(9), confidence: 0.9)
        )
        let plan = PlanFixtures.valid(
            subject: SubjectPlan(
                targetX: 0.9,
                targetY: 0.9,
                targetHeight: 0.8,
                bodyYaw: .degrees(-30)
            ),
            camera: CameraPlan(heightAdjustment: -0.5)
        )

        let cues = engine.guidance(for: scene, plan: plan).guidance.cues

        // A human cannot act on five simultaneous corrections.
        #expect(cues.count <= GuidancePolicy.default.maximumCues)
    }

    @Test("The highest-priority correction wins when an actor has several")
    func highestPriorityCueWinsPerActor() {
        let subject = SceneFixtures.subject(
            bounds: NormalizedRect(x: 0.05, y: 0.3, width: 0.1, height: 0.2)
        )
        let scene = SceneFixtures.scene(subjects: [subject])
        let plan = PlanFixtures.valid(
            subject: SubjectPlan(targetX: 0.9, targetHeight: 0.8)
        )

        let cue = engine.guidance(for: scene, plan: plan).guidance.cue(for: .photographer)

        // Placement outranks distance.
        #expect(cue?.axis == .panRight)
    }

    // MARK: Levelling

    @Test("Roll beyond tolerance produces an exact levelling rotation")
    func levellingUsesExactRoll() {
        let scene = SceneFixtures.scene(
            subjects: [],
            horizon: HorizonEstimate(normalizedY: 0.5, roll: .degrees(6), confidence: 0.95)
        )

        let cue = engine.guidance(for: scene, plan: PlanFixtures.empty).guidance.cue(for: .camera)

        #expect(cue?.axis == .rollLevel)
        // Gravity gives roll exactly, so this is metric-accurate with no depth at all.
        guard case let .degrees(angle, _)? = cue?.rotation else {
            Issue.record("expected an exact roll correction")
            return
        }
        #expect(abs(angle.degrees + 6) < 1e-9)
    }

    @Test("A level horizon produces no levelling cue")
    func levelHorizonIsSilent() {
        let scene = SceneFixtures.scene(
            horizon: HorizonEstimate(normalizedY: 0.5, roll: .degrees(0.2), confidence: 0.95)
        )

        let cue = engine.guidance(for: scene, plan: PlanFixtures.empty).guidance.cue(for: .camera)

        #expect(cue == nil)
    }

    // MARK: Readiness

    @Test("Readiness reports the blocking cue when something is wrong")
    func blockedReadinessCarriesTheCue() {
        let scene = SceneFixtures.scene()
        let plan = PlanFixtures.valid(subject: SubjectPlan(targetX: 0.9))

        let readiness = engine.guidance(for: scene, plan: plan).guidance.readiness

        guard case let .blocked(cue) = readiness else {
            Issue.record("expected a blocked readiness")
            return
        }
        #expect(cue.axis == .panRight)
    }

    @Test("Meeting every expressed target reports ready")
    func meetingTargetsIsReady() {
        let subject = SceneFixtures.subject(
            bounds: NormalizedRect(x: 0.55, y: 0.3, width: 0.15, height: 0.4)
        )
        let scene = SceneFixtures.scene(subjects: [subject])
        // Subject centre is (0.625, 0.5); ask for exactly that.
        let plan = PlanFixtures.valid(subject: SubjectPlan(
            targetX: 0.625,
            targetY: 0.5,
            targetHeight: 0.4
        ))

        let output = engine.guidance(for: scene, plan: plan)

        #expect(output.guidance.cues.isEmpty)
        #expect(output.guidance.readiness == .ready)
    }

    // MARK: Determinism

    @Test("The same inputs always produce the same output")
    func isDeterministic() {
        let scene = SceneFixtures.scene(
            horizon: HorizonEstimate(normalizedY: 0.4, roll: .degrees(5), confidence: 0.9)
        )
        let plan = PlanFixtures.valid(
            subject: SubjectPlan(targetX: 0.8, targetHeight: 0.7),
            camera: CameraPlan(heightAdjustment: -0.3)
        )

        let first = engine.guidance(for: scene, plan: plan)
        let second = engine.guidance(for: scene, plan: plan)

        // Purity is what makes recorded-session replay reproducible.
        #expect(first == second)
    }

    @Test("The policy's hysteresis bands are actually bands")
    func policyHysteresisIsValid() {
        // An exit tolerance at or below its enter tolerance silently removes the
        // hysteresis and reintroduces flicker.
        #expect(GuidancePolicy.default.hasValidHysteresis)
    }

    // MARK: Overlay

    @Test("The overlay carries photographic intent without detector boxes")
    func overlayCarriesPhotographicIntent() {
        let scene = SceneFixtures.scene(
            horizon: HorizonEstimate(normalizedY: 0.55, roll: .zero, confidence: 0.9)
        )
        let plan = PlanFixtures.valid(
            selection: SubjectSelection(
                kind: .person,
                visualAnchor: NormalizedPoint(x: 0.42, y: 0.31)
            ),
            framing: FramingPlan(
                targetFrame: NormalizedRect(x: 0.14, y: 0.12, width: 0.72, height: 0.76)
            ),
            displayAdvice: ["Keep the eyes clear"],
            scene: ScenePlan(targetHorizon: 0.34)
        )

        let guidance = engine.guidance(for: scene, plan: plan).guidance
        let overlay = guidance.overlay

        #expect(overlay.visualAnchor == NormalizedPoint(x: 0.42, y: 0.31))
        #expect(overlay.targetFrame == NormalizedRect(
            x: 0.14,
            y: 0.12,
            width: 0.72,
            height: 0.76
        ))
        #expect(overlay.targetHorizonY == 0.34)
        #expect(overlay.currentHorizonY == 0.55)
        #expect(guidance.displayAdvice == ["Keep the eyes clear"])
    }
}
