import ForgeCore

/// A deterministic frame source advanced explicitly by a test or replay driver.
///
/// Explicit advancement avoids wall-clock sleeps and detached playback tasks. A replay
/// driver advances only after processing the previous frame; tests may advance faster
/// to verify the live source's newest-frame buffering contract.
public actor RecordedFrameSource<Content: Sendable>: FrameSource {
    // SwiftFormat puts access control before isolation; SwiftLint's modifier-order
    // rule expects the reverse. The formatter is the writer, so suppress this one
    // irreconcilable lint check rather than create formatting churn.
    // swiftlint:disable:next modifier_order
    public nonisolated let frames: AsyncStream<SceneFrame<Content>>

    private enum State {
        case idle
        case running
        case finished
    }

    private let recordedFrames: [SceneFrame<Content>]
    private let continuation: AsyncStream<SceneFrame<Content>>.Continuation
    private var nextIndex = 0
    private var state = State.idle
    private var runID: UInt64 = 0

    /// The run currently delivering frames.
    public var currentRunID: UInt64 {
        runID
    }

    /// Creates a source whose first `start()` emits the first recorded frame.
    public init(frames recordedFrames: [SceneFrame<Content>]) {
        let stream = AsyncStream<SceneFrame<Content>>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        frames = stream.stream
        continuation = stream.continuation
        self.recordedFrames = recordedFrames
    }

    deinit {
        continuation.finish()
    }

    /// Begins or resumes explicit frame advancement.
    public func start() async throws {
        switch state {
        case .idle:
            // Matches the live source: resuming delivery begins a new run, so any
            // frame still buffered from before the stop is recognisably stale.
            runID &+= 1
            state = .running
            _ = emitNext()
        case .running, .finished:
            break
        }
    }

    /// Pauses advancement without rewinding or terminating the stream.
    public func stop() async {
        guard state == .running else { return }
        state = .idle
    }

    /// Emits exactly one recorded frame when running.
    ///
    /// Returns `true` when a frame was accepted by the stream. Reaching the end is
    /// terminal; construct a new source to replay from the beginning.
    @discardableResult
    public func advance() -> Bool {
        guard state == .running else { return false }
        return emitNext()
    }

    private func emitNext() -> Bool {
        guard nextIndex < recordedFrames.count else {
            finish()
            return false
        }

        // Stamped with the run that is delivering, not the run it was recorded in.
        let frame = recordedFrames[nextIndex].stamped(runID: runID)
        nextIndex += 1

        switch continuation.yield(frame) {
        case .enqueued, .dropped:
            if nextIndex == recordedFrames.count {
                finish()
            }
            return true
        case .terminated:
            state = .finished
            return false
        @unknown default:
            state = .finished
            return false
        }
    }

    private func finish() {
        state = .finished
        continuation.finish()
    }
}
