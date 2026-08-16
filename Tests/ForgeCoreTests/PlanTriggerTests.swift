import ForgeTestSupport
import Testing
@testable import ForgeCore

@Suite("Plan trigger")
struct PlanTriggerTests {
    let trigger = PlanTrigger()

    private func scene(
        at time: Double,
        subjects: [DetectedSubject] = [SceneFixtures.subject()]
    ) -> SceneState {
        SceneFixtures.scene(timestamp: time, subjects: subjects)
    }

    // MARK: Cold start and expiry

    @Test("With no plan latched, a request fires immediately")
    func coldStartRequests() {
        let decision = trigger.evaluate(scene: scene(at: 0), plan: nil, state: .initial)

        #expect(decision.shouldRequest)
        #expect(decision.reason == .noPlan)
        #expect(decision.state.hasRequestInFlight)
    }

    @Test("A fresh plan and an unchanged scene produce no request")
    func freshPlanIsLeftAlone() {
        let state = PlanTrigger.State(
            planIssuedAt: 0,
            lastRequestAt: 0,
            sceneAtLastRequest: scene(at: 0),
            hasRequestInFlight: false
        )

        let decision = trigger.evaluate(
            scene: scene(at: 5),
            plan: PlanFixtures.valid(),
            state: state
        )

        #expect(!decision.shouldRequest)
        #expect(decision.reason == nil)
    }

    @Test("A plan past its lifetime triggers a replan")
    func expiredPlanTriggersReplan() {
        let plan = PlanFixtures.valid()
        let state = PlanTrigger.State(
            planIssuedAt: 0,
            lastRequestAt: 0,
            sceneAtLastRequest: scene(at: 0),
            hasRequestInFlight: false
        )

        // The fixture plan declares a 20 second lifetime.
        let decision = trigger.evaluate(scene: scene(at: 25), plan: plan, state: state)

        #expect(decision.shouldRequest)
        #expect(decision.reason == .planExpired)
    }

    @Test("The plan's own lifetime wins over the policy default")
    func planLifetimeOverridesPolicyDefault() {
        let shortLived = CompositionPlan(
            planId: "p",
            intent: .portrait,
            subject: SubjectPlan(targetX: 0.5),
            expiresAfterSeconds: 2
        )
        let state = PlanTrigger.State(
            planIssuedAt: 0,
            lastRequestAt: 0,
            sceneAtLastRequest: scene(at: 0),
            hasRequestInFlight: false
        )

        let decision = trigger.evaluate(scene: scene(at: 3), plan: shortLived, state: state)

        #expect(decision.reason == .planExpired)
    }

    // MARK: In-flight coalescing

    @Test("A request in flight suppresses further requests rather than queueing them")
    func inFlightRequestsCoalesce() {
        let state = PlanTrigger.State(hasRequestInFlight: true)

        let decision = trigger.evaluate(scene: scene(at: 100), plan: nil, state: state)

        // A busy scene must not be able to build a backlog of stale plans.
        #expect(!decision.shouldRequest)
    }

    @Test("Completing a request clears the in-flight flag and records the plan time")
    func completingRequestUpdatesState() {
        let state = PlanTrigger.State(hasRequestInFlight: true)

        let next = trigger.requestCompleted(at: 12, producedPlan: true, state: state)

        #expect(!next.hasRequestInFlight)
        #expect(next.planIssuedAt == 12)
    }

    @Test("A failed request still clears the in-flight flag")
    func failedRequestDoesNotWedgeTheTrigger() {
        let state = PlanTrigger.State(planIssuedAt: 1, hasRequestInFlight: true)

        let next = trigger.requestCompleted(at: 12, producedPlan: false, state: state)

        // Otherwise one dropped request stops the app ever planning again.
        #expect(!next.hasRequestInFlight)
        #expect(next.planIssuedAt == 1)
    }

    // MARK: Rate limiting

    @Test("Requests are rate limited")
    func rateLimitSuppressesRapidRequests() {
        let state = PlanTrigger.State(
            planIssuedAt: nil,
            lastRequestAt: 10,
            sceneAtLastRequest: scene(at: 10),
            hasRequestInFlight: false
        )

        // 0.1s after the last request, well inside the 0.5s minimum interval.
        let decision = trigger.evaluate(scene: scene(at: 10.1), plan: nil, state: state)

        #expect(!decision.shouldRequest)
    }

    @Test("An explicit user request bypasses the rate limit")
    func userRequestBypassesRateLimit() {
        let state = PlanTrigger.State(
            planIssuedAt: 10,
            lastRequestAt: 10,
            sceneAtLastRequest: scene(at: 10),
            hasRequestInFlight: false
        )

        let decision = trigger.evaluate(
            scene: scene(at: 10.1),
            plan: PlanFixtures.valid(),
            events: PlanTrigger.Events(userRequested: true),
            state: state
        )

        // Someone who taps a button and gets nothing concludes the app is broken.
        #expect(decision.shouldRequest)
        #expect(decision.reason == .userRequested)
    }

    @Test("Finishing a capture triggers the review and retake loop")
    func captureCompletionTriggersReplan() {
        let state = PlanTrigger.State(
            planIssuedAt: 0,
            lastRequestAt: 0,
            sceneAtLastRequest: scene(at: 0),
            hasRequestInFlight: false
        )

        let decision = trigger.evaluate(
            scene: scene(at: 5),
            plan: PlanFixtures.valid(),
            events: PlanTrigger.Events(captureCompleted: true),
            state: state
        )

        #expect(decision.reason == .captureCompleted)
    }

    // MARK: Material change detection

    @Test("A subject appearing or leaving is material")
    func subjectCountChangeIsMaterial() {
        let before = scene(at: 0, subjects: [SceneFixtures.subject()])
        let after = scene(at: 1, subjects: [
            SceneFixtures.subject(id: "a"),
            SceneFixtures.subject(id: "b", salience: 0.8),
        ])

        #expect(trigger.materialChange(from: before, to: after) == .subjectCountChanged)
    }

    @Test("A small subject movement is not material")
    func smallMovementIsIgnored() {
        let before = scene(at: 0, subjects: [
            SceneFixtures.subject(bounds: NormalizedRect(x: 0.2, y: 0.3, width: 0.15, height: 0.4)),
        ])
        let after = scene(at: 1, subjects: [
            SceneFixtures.subject(bounds: NormalizedRect(
                x: 0.22,
                y: 0.3,
                width: 0.15,
                height: 0.4
            )),
        ])

        // Replanning on every twitch makes the target visibly move while the user is
        // trying to reach it.
        #expect(trigger.materialChange(from: before, to: after) == nil)
    }

    @Test("A large subject movement is material")
    func largeMovementIsMaterial() {
        let before = scene(at: 0, subjects: [
            SceneFixtures.subject(bounds: NormalizedRect(x: 0.1, y: 0.3, width: 0.15, height: 0.4)),
        ])
        let after = scene(at: 1, subjects: [
            SceneFixtures.subject(bounds: NormalizedRect(x: 0.6, y: 0.3, width: 0.15, height: 0.4)),
        ])

        #expect(trigger.materialChange(from: before, to: after) == .subjectMoved)
    }

    @Test("A large change in subject size is material")
    func subjectResizeIsMaterial() {
        // Both rects share the centre (0.25, 0.4), so only the size changes. Growing a
        // rect from its origin would also shift its centre and trip `subjectMoved`
        // first, which would test the wrong thing.
        let before = scene(at: 0, subjects: [
            SceneFixtures.subject(bounds: NormalizedRect(x: 0.2, y: 0.3, width: 0.1, height: 0.2)),
        ])
        let after = scene(at: 1, subjects: [
            SceneFixtures.subject(bounds: NormalizedRect(
                x: 0.15,
                y: 0.15,
                width: 0.2,
                height: 0.5
            )),
        ])

        #expect(before.primarySubject?.bounds.center == after.primarySubject?.bounds.center)
        #expect(trigger.materialChange(from: before, to: after) == .subjectResized)
    }

    @Test("A one-stop lighting change is material")
    func lightingChangeIsMaterial() {
        let before = SceneFixtures.scene(
            timestamp: 0,
            lighting: LightingEstimate(
                meanLuma: 0.5,
                clippedHighlightFraction: 0,
                clippedShadowFraction: 0
            )
        )
        let after = SceneFixtures.scene(
            timestamp: 1,
            lighting: LightingEstimate(
                meanLuma: 0.2,
                clippedHighlightFraction: 0,
                clippedShadowFraction: 0
            )
        )

        #expect(trigger.materialChange(from: before, to: after) == .lightingChanged)
    }

    @Test("Camera movement counts only when the position is genuinely metric")
    func cameraMovementRequiresMetricProvenance() {
        func sceneWith(position: Measured<Vector3>, at time: Double) -> SceneState {
            SceneFixtures.scene(
                timestamp: time,
                motion: DeviceMotionState(
                    roll: .zero,
                    pitch: .zero,
                    position: position,
                    coupling: .rigid
                )
            )
        }

        let origin = Vector3(x: 0, y: 0, z: 0)
        let moved = Vector3(x: 2, y: 0, z: 0)

        let metricBefore = sceneWith(
            position: Measured(value: origin, confidence: 0.9, provenance: .arkitPose),
            at: 0
        )
        let metricAfter = sceneWith(
            position: Measured(value: moved, confidence: 0.9, provenance: .arkitPose),
            at: 1
        )
        #expect(trigger.materialChange(from: metricBefore, to: metricAfter) == .cameraMoved)

        // The same displacement from a non-metric source proves nothing about metres.
        let guessedBefore = sceneWith(
            position: Measured(value: origin, confidence: 0.9, provenance: .estimated),
            at: 0
        )
        let guessedAfter = sceneWith(
            position: Measured(value: moved, confidence: 0.9, provenance: .estimated),
            at: 1
        )
        #expect(trigger.materialChange(from: guessedBefore, to: guessedAfter) == nil)
    }

    @Test("A focal length change is material")
    func focalLengthChangeIsMaterial() {
        let before = SceneFixtures.scene(timestamp: 0, camera: CameraState(focalLength: 35))
        let after = SceneFixtures.scene(timestamp: 1, camera: CameraState(focalLength: 85))

        #expect(trigger.materialChange(from: before, to: after) == .focalLengthChanged)
    }

    @Test("An identical scene is never a material change")
    func identicalSceneIsNotMaterial() {
        let state = scene(at: 0)
        #expect(trigger.materialChange(from: state, to: state) == nil)
    }

    // MARK: Cadence

    @Test("A still scene does not exceed the policy's request rate over a long run")
    func staleSceneStaysWithinRateCap() {
        var state = PlanTrigger.State.initial
        var requests = 0

        // Ten seconds at 30 FPS with a completely static scene.
        for frame in 0 ..< 300 {
            let time = Double(frame) / 30
            let decision = trigger.evaluate(
                scene: scene(at: time),
                plan: PlanFixtures.valid(),
                state: state
            )
            state = decision.state
            if decision.shouldRequest {
                requests += 1
                state = trigger.requestCompleted(at: time, producedPlan: true, state: state)
            }
        }

        // One cold start, then silence: the plan never expires within the window and
        // nothing in the scene changes.
        #expect(requests == 1)
    }
}
