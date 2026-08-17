import Foundation

/// Drives the whole live loop: frames in, guidance out.
///
/// The three rates live here and stay separate. Perception runs per frame, the
/// director is consulted on an event trigger, and guidance is recomputed from the
/// latched plan every frame. A slow, failed, or absent plan never stalls the loop —
/// guidance simply runs against whatever plan is currently latched.
///
/// The pipeline owns no platform types. It composes a `FrameSource`, a
/// `SceneAnalyzer`, and a `DirectorProvider`, which is what lets the same loop run on
/// live camera frames, on a recorded session, and in a test.
public actor CapturePipeline<Source: FrameSource, Analyzer: SceneAnalyzer>
    where Source.FrameContent == Analyzer.FrameContent {
    /// When a plan request is allowed to complete relative to the frame loop.
    public enum PlanningMode: Sendable {
        /// Planning runs detached, so a slow director never stalls the frame loop.
        ///
        /// The plan therefore lands on whichever frame happens to follow the reply,
        /// which is correct for live capture and inherently non-deterministic.
        case concurrent

        /// Planning completes before the next frame is processed.
        ///
        /// Required for replay: a recorded session must produce a byte-identical
        /// guidance sequence every time, and it cannot if plan arrival races the
        /// loop. Only safe when the director is fast and local, as it is in replay.
        case synchronous
    }

    /// Everything the interface needs for one frame.
    public struct Update: Sendable {
        public let scene: SceneState
        public let guidance: GuidanceState
        /// The plan guidance was computed against, if one is latched.
        public let plan: CompositionPlan?
        /// Why the director was last consulted. `nil` when no request has been made.
        public let lastPlanReason: PlanTrigger.Reason?
    }

    private let source: Source
    private let analyzer: Analyzer
    private let director: any DirectorProvider
    private let guidanceEngine: GuidanceEngine
    private let trigger: PlanTrigger
    private let validator: PlanValidator
    private let validationContext: PlanValidator.Context
    private let planningMode: PlanningMode

    private let updateContinuation: AsyncStream<Update>.Continuation
    /// One update per analyzed frame, newest-one buffered like the frame stream.
    ///
    /// SwiftFormat puts access control before isolation; SwiftLint's modifier-order
    /// rule expects the reverse. The formatter is the writer, so the lint check is
    /// suppressed inline — placing the suppression on its own line above would
    /// detach this doc comment from the declaration.
    public nonisolated let updates: AsyncStream<Update> // swiftlint:disable:this modifier_order

    // Latched state, actor-isolated.
    private var plan: CompositionPlan?
    private var triggerState = PlanTrigger.State.initial
    private var guidanceMemory = GuidanceEngine.MemoryState.initial
    private var previousScene: SceneState?
    private var lastPlanReason: PlanTrigger.Reason?
    private var planningTask: Task<Void, Never>?
    private var isRunning = false
    /// Sequential rather than a UUID.
    ///
    /// A random request id reaches the plan id, and from there into `GuidanceState`,
    /// which makes two replays of the same recorded session differ. Request ids only
    /// need to be unique within a session, so a counter satisfies that while keeping
    /// the loop free of any randomness at all.
    private var nextRequestNumber = 0

    /// Counters for diagnostics. Frames analyzed versus skipped is the honest measure
    /// of what the loop actually kept up with.
    public private(set) var framesAnalyzed = 0
    public private(set) var framesDroppedAsStale = 0

    public init(
        source: Source,
        analyzer: Analyzer,
        director: any DirectorProvider,
        guidanceEngine: GuidanceEngine = GuidanceEngine(),
        trigger: PlanTrigger = PlanTrigger(),
        validator: PlanValidator = PlanValidator(),
        validationContext: PlanValidator.Context = .unconstrained,
        planningMode: PlanningMode = .concurrent
    ) {
        self.source = source
        self.analyzer = analyzer
        self.director = director
        self.guidanceEngine = guidanceEngine
        self.trigger = trigger
        self.validator = validator
        self.validationContext = validationContext
        self.planningMode = planningMode

        let channel = AsyncStream<Update>.makeStream(bufferingPolicy: .bufferingNewest(1))
        updates = channel.stream
        updateContinuation = channel.continuation
    }

    deinit {
        planningTask?.cancel()
        updateContinuation.finish()
    }

    /// Starts the source and consumes frames until the stream ends or the task is
    /// cancelled. Returns when frame delivery finishes.
    public func run() async throws {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        try await source.start()

        for await frame in source.frames {
            if Task.isCancelled {
                break
            }

            // A producer cannot empty an AsyncStream's buffer, so a frame captured
            // before the last stop can still arrive here. Acting on it would analyze
            // a scene the user has already moved away from.
            guard await source.isCurrent(frame) else {
                framesDroppedAsStale += 1
                continue
            }

            await process(frame)
        }
    }

    /// Stops the source and cancels any planning request in flight.
    public func stop() async {
        planningTask?.cancel()
        planningTask = nil
        await source.stop()
        triggerState = trigger.requestCompleted(
            at: previousScene?.timestamp ?? 0,
            producedPlan: false,
            state: triggerState
        )
    }

    /// The current latched plan, for a caller that needs it outside an update.
    public var latchedPlan: CompositionPlan? {
        plan
    }

    // MARK: - Per-frame work

    private func process(_ frame: SceneFrame<Source.FrameContent>) async {
        let scene = await analyzer.analyze(frame, previous: previousScene)
        previousScene = scene
        framesAnalyzed += 1

        // Guidance is recomputed every frame from the latched plan. This is the fast
        // loop, and it must not wait on the director.
        let output = guidanceEngine.guidance(for: scene, plan: plan, memory: guidanceMemory)
        guidanceMemory = output.memory

        updateContinuation.yield(Update(
            scene: scene,
            guidance: output.guidance,
            plan: plan,
            lastPlanReason: lastPlanReason
        ))

        await requestPlanIfNeeded(for: scene)
    }

    private func requestPlanIfNeeded(for scene: SceneState) async {
        let decision = trigger.evaluate(
            scene: scene,
            plan: plan,
            events: .none,
            state: triggerState
        )
        triggerState = decision.state
        guard decision.shouldRequest else { return }
        lastPlanReason = decision.reason

        switch planningMode {
        case .concurrent:
            // Detached on purpose: the director runs orders of magnitude slower than
            // perception, and the frame loop must never wait for it.
            planningTask = Task { [weak self] in
                await self?.performPlanRequest(for: scene)
            }
        case .synchronous:
            await performPlanRequest(for: scene)
        }
    }

    private func performPlanRequest(for scene: SceneState) async {
        nextRequestNumber += 1
        let request = DirectorRequest(
            requestId: "request-\(nextRequestNumber)",
            scene: scene,
            intentHint: nil,
            previousPlanId: plan?.planId
        )

        var produced = false
        do {
            let proposed = try await director.plan(request)
            let result = try validator.validate(proposed, context: validationContext)
            plan = result.plan
            produced = true
        } catch is CancellationError {
            // A cancelled request is not a failure; the previous plan stays latched.
        } catch {
            // A director that fails leaves the previous plan in place. Guidance keeps
            // running on it rather than going blank, which is the whole point of
            // latching. See the no-backend degradation requirement.
        }

        triggerState = trigger.requestCompleted(
            at: scene.timestamp,
            producedPlan: produced,
            state: triggerState
        )
    }

    /// Forces a replan, bypassing the rate limit, as a user tap does.
    public func requestReplan() {
        guard let scene = previousScene else { return }
        let decision = trigger.evaluate(
            scene: scene,
            plan: plan,
            events: PlanTrigger.Events(userRequested: true),
            state: triggerState
        )
        triggerState = decision.state
        guard decision.shouldRequest else { return }
        lastPlanReason = decision.reason
        planningTask = Task { [weak self] in
            await self?.performPlanRequest(for: scene)
        }
    }
}
