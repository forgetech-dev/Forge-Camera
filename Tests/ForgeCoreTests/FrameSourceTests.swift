import ForgeTestSupport
import Foundation
import Testing
@testable import ForgeCore

@Suite("Frame source contract")
struct FrameSourceTests {
    @Test("Recorded frames preserve sequence, timestamps, geometry, and content")
    func recordedFramesPreserveValues() async throws {
        let expected = makeFrame(sequenceNumber: 7, timestamp: 1.25, content: "frame-seven")
        let source = RecordedFrameSource(frames: [expected])
        var iterator = source.frames.makeAsyncIterator()

        try await source.start()

        let delivered = try #require(await iterator.next())
        // The run stamp is applied by whoever delivers the frame, not by whoever
        // recorded it, so it is compared against the source rather than the fixture.
        let runID = await source.currentRunID
        #expect(delivered == expected.stamped(runID: runID))
        #expect(await iterator.next() == nil)
    }

    @Test("Starting repeatedly does not duplicate or skip a frame")
    func repeatedStartIsIdempotent() async throws {
        let frames = [
            makeFrame(sequenceNumber: 0, timestamp: 0, content: "first"),
            makeFrame(sequenceNumber: 1, timestamp: 1, content: "second"),
        ]
        let source = RecordedFrameSource(frames: frames)
        var iterator = source.frames.makeAsyncIterator()

        try await source.start()
        try await source.start()
        #expect(await iterator.next()?.sequenceNumber == 0)

        #expect(await source.advance())
        #expect(await iterator.next()?.sequenceNumber == 1)
        #expect(await iterator.next() == nil)
    }

    @Test("Stopping pauses delivery and starting resumes at the next frame")
    func stopAndResume() async throws {
        let frames = [
            makeFrame(sequenceNumber: 0, timestamp: 0, content: "first"),
            makeFrame(sequenceNumber: 1, timestamp: 1, content: "second"),
        ]
        let source = RecordedFrameSource(frames: frames)
        var iterator = source.frames.makeAsyncIterator()

        try await source.start()
        #expect(await iterator.next()?.sequenceNumber == 0)

        await source.stop()
        #expect(await !(source.advance()))

        try await source.start()
        #expect(await iterator.next()?.sequenceNumber == 1)
        #expect(await iterator.next() == nil)
    }

    @Test("An empty recording finishes immediately")
    func emptyRecordingFinishes() async throws {
        let source = RecordedFrameSource<String>(frames: [])
        var iterator = source.frames.makeAsyncIterator()

        try await source.start()

        #expect(await iterator.next() == nil)
        #expect(await !(source.advance()))
    }

    @Test("The stream keeps only the newest frame for a slow consumer")
    func latestFrameWins() async throws {
        let frames = [
            makeFrame(sequenceNumber: 0, timestamp: 0, content: "first"),
            makeFrame(sequenceNumber: 1, timestamp: 1, content: "second"),
            makeFrame(sequenceNumber: 2, timestamp: 2, content: "third"),
        ]
        let source = RecordedFrameSource(frames: frames)
        var iterator = source.frames.makeAsyncIterator()

        try await source.start()
        #expect(await source.advance())
        #expect(await source.advance())

        let delivered = try #require(await iterator.next())
        #expect(delivered.sequenceNumber == 2)
        #expect(delivered.content == "third")
        #expect(await iterator.next() == nil)
    }

    private func makeFrame(
        sequenceNumber: UInt64,
        timestamp: TimeInterval,
        content: String
    ) -> SceneFrame<String> {
        SceneFrame(
            sequenceNumber: sequenceNumber,
            timestamp: timestamp,
            geometry: SceneFixtures.landscapeFrame,
            content: content
        )
    }
}

@Suite("Frame run identity")
struct FrameRunIdentityTests {
    private func makeFrame(
        sequenceNumber: UInt64,
        timestamp: TimeInterval,
        content: String
    ) -> SceneFrame<String> {
        SceneFrame(
            sequenceNumber: sequenceNumber,
            timestamp: timestamp,
            geometry: SceneFixtures.landscapeFrame,
            content: content
        )
    }

    private func frames(_ count: Int) -> [SceneFrame<String>] {
        (0 ..< count).map {
            makeFrame(sequenceNumber: UInt64($0), timestamp: Double($0), content: "frame-\($0)")
        }
    }

    @Test("Resuming delivery starts a new run")
    func restartBeginsNewRun() async throws {
        let source = RecordedFrameSource(frames: frames(3))

        #expect(await source.currentRunID == 0)
        try await source.start()
        let first = await source.currentRunID
        await source.stop()
        try await source.start()
        let second = await source.currentRunID

        #expect(first == 1)
        #expect(second == 2)
    }

    @Test("A frame from an earlier run is not current")
    func earlierRunIsNotCurrent() async throws {
        let source = RecordedFrameSource(frames: frames(3))
        var iterator = source.frames.makeAsyncIterator()

        try await source.start()
        let fromFirstRun = try #require(await iterator.next())
        await source.stop()
        try await source.start()

        // This is the frame an AsyncStream can still hand a consumer after a restart:
        // the producer cannot withdraw it, so the consumer has to recognise it.
        #expect(await source.isCurrent(fromFirstRun) == false)
    }

    @Test("A frame from the delivering run is current")
    func currentRunIsCurrent() async throws {
        let source = RecordedFrameSource(frames: frames(3))
        var iterator = source.frames.makeAsyncIterator()

        try await source.start()
        let frame = try #require(await iterator.next())

        #expect(await source.isCurrent(frame))
    }

    @Test("Re-stamping changes only the run")
    func stampingPreservesEverythingElse() {
        let original = makeFrame(sequenceNumber: 4, timestamp: 2.5, content: "payload")
        let stamped = original.stamped(runID: 9)

        #expect(stamped.runID == 9)
        #expect(stamped.sequenceNumber == original.sequenceNumber)
        #expect(stamped.timestamp == original.timestamp)
        #expect(stamped.geometry == original.geometry)
        #expect(stamped.content == original.content)
    }
}
