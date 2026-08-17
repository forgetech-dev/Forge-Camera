import ForgeTestSupport
import Foundation
import Testing
@testable import ForgeCore

@Suite("Capture pipeline")
struct CapturePipelineTests {
    private typealias Pipeline = CapturePipeline<
        RecordedFrameSource<String>,
        StubSceneAnalyzer<String>
    >

    private func frames(_ count: Int, spacing: TimeInterval = 1.0 / 30) -> [SceneFrame<String>] {
        (0 ..< count).map { index in
            SceneFrame(
                sequenceNumber: UInt64(index),
                timestamp: Double(index) * spacing,
                geometry: SceneFixtures.landscapeFrame,
                content: "frame-\(index)"
            )
        }
    }

    /// Drives the pipeline one frame at a time and collects an update for each.
    ///
    /// Advancing and awaiting in lockstep is what makes this deterministic. Advancing
    /// freely would race the pipeline's start and drop frames from the newest-one
    /// buffer, so the counts would depend on scheduling rather than on behaviour.
    private func drain(
        frameCount: Int,
        director: any DirectorProvider = HeuristicDirector(),
        analyzer: StubSceneAnalyzer<String> = StubSceneAnalyzer(),
        planningMode: Pipeline.PlanningMode = .concurrent
    ) async throws -> (updates: [Pipeline.Update], pipeline: Pipeline) {
        let source = RecordedFrameSource(frames: frames(frameCount))
        let pipeline = CapturePipeline(
            source: source,
            analyzer: analyzer,
            director: director,
            planningMode: planningMode
        )
        var iterator = pipeline.updates.makeAsyncIterator()

        let running = Task { try await pipeline.run() }

        // `run()` starts the source. Advancing before that would find it idle.
        while await source.currentRunID == 0 {
            await Task.yield()
        }

        var updates: [Pipeline.Update] = []
        // `start()` already emitted the first frame.
        if let first = await iterator.next() {
            updates.append(first)
        }
        while await source.advance() {
            if let next = await iterator.next() {
                updates.append(next)
            }
        }

        try await running.value
        return (updates, pipeline)
    }

    // MARK: Wiring

    @Test("Every live frame produces one guidance update")
    func everyFrameProducesAnUpdate() async throws {
        let (updates, pipeline) = try await drain(frameCount: 5)

        #expect(updates.count == 5)
        #expect(await pipeline.framesAnalyzed == 5)
    }

    @Test("Guidance is recomputed per frame while planning stays rare")
    func planningIsRarerThanGuidance() async throws {
        let director = CountingDirectorProvider()
        let (updates, _) = try await drain(frameCount: 8, director: director)

        // The trigger policy is the whole reason a slow director does not slow the
        // loop: many frames, few consultations.
        #expect(updates.count == 8)
        #expect(await director.callCount >= 1)
        #expect(await director.callCount < updates.count)
    }

    @Test("A latched plan reaches guidance and produces cues")
    func latchedPlanReachesGuidance() async throws {
        let (updates, _) = try await drain(frameCount: 10)

        let planned = updates.filter { $0.plan != nil }
        #expect(!planned.isEmpty)
        // The stub subject sits well off the heuristic target, so once a plan exists
        // guidance must have something to say about it.
        #expect(planned.contains { !$0.guidance.cues.isEmpty })
    }

    @Test("Scene state flows from the analyzer into the update")
    func sceneStateReachesTheUpdate() async throws {
        let bounds = NormalizedRect(x: 0.6, y: 0.2, width: 0.2, height: 0.5)
        let (updates, _) = try await drain(
            frameCount: 3,
            analyzer: StubSceneAnalyzer(subjectBounds: bounds)
        )

        #expect(updates.allSatisfy { $0.scene.primarySubject?.bounds == bounds })
    }

    // MARK: Degradation

    @Test("A failing director leaves the loop running with no plan")
    func failingDirectorDoesNotStopTheLoop() async throws {
        let (updates, pipeline) = try await drain(
            frameCount: 5,
            director: FailingDirectorProvider()
        )

        // The app must stay useful with no backend: frames keep flowing and guidance
        // keeps being produced, it simply has no plan to aim at.
        #expect(updates.count == 5)
        #expect(await pipeline.latchedPlan == nil)
        #expect(updates.allSatisfy { $0.plan == nil })
    }

    @Test("A director failure never propagates out of run()")
    func directorFailureIsContained() async throws {
        // `run()` returning normally is the assertion.
        let (updates, _) = try await drain(frameCount: 3, director: FailingDirectorProvider())
        #expect(updates.count == 3)
    }

    // MARK: Stale frames

    @Test("A clean run drops nothing as stale")
    func cleanRunDropsNothing() async throws {
        let (_, pipeline) = try await drain(frameCount: 4)

        #expect(await pipeline.framesDroppedAsStale == 0)
        #expect(await pipeline.framesAnalyzed == 4)
    }

    @Test("A frame stamped with an earlier run is rejected before analysis")
    func staleFrameIsRejected() async throws {
        // The pipeline's guard is `source.isCurrent(frame)`. Proving the rule holds at
        // the source boundary is what keeps a pre-restart frame out of scene state.
        let source = RecordedFrameSource(frames: frames(3))
        var iterator = source.frames.makeAsyncIterator()

        try await source.start()
        let fromFirstRun = try #require(await iterator.next())
        await source.stop()
        try await source.start()

        #expect(await source.isCurrent(fromFirstRun) == false)
    }

    // MARK: Determinism

    @Test("Replay with synchronous planning is byte-identical")
    func replayIsDeterministic() async throws {
        func runOnce() async throws -> [GuidanceState] {
            let (updates, _) = try await drain(frameCount: 6, planningMode: .synchronous)
            return updates.map(\.guidance)
        }

        // Determinism is what makes recorded-session regression testing possible (N-09),
        // and it requires `.synchronous`: under `.concurrent` the plan lands on whichever
        // frame follows the director's reply, which is a race by design.
        let first = try await runOnce()
        let second = try await runOnce()

        #expect(first == second)
        #expect(!first.isEmpty)
    }

    @Test("Live planning does not block the frame loop")
    func concurrentPlanningDoesNotBlockFrames() async throws {
        // The counterpart guarantee: under `.concurrent` every frame is still
        // analyzed and delivered, whatever the director is doing.
        let (updates, pipeline) = try await drain(frameCount: 6, planningMode: .concurrent)

        #expect(updates.count == 6)
        #expect(await pipeline.framesAnalyzed == 6)
    }
}
