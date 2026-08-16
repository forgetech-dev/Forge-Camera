import Foundation

/// One orientation-corrected frame delivered by a `FrameSource`.
///
/// The content is generic so the Foundation-only domain can describe frame delivery
/// without importing a platform image type. Production capture uses an owned pixel
/// buffer while deterministic replay can use a lightweight value payload.
public struct SceneFrame<Content: Sendable>: Sendable {
    /// Identifies the continuous delivery run that produced this frame.
    ///
    /// A producer cannot empty an `AsyncStream`'s buffer, so a frame captured just
    /// before `stop()` can still be delivered after the source restarts. Comparing
    /// this against the source's `currentRunID` is how a consumer recognises such a
    /// frame as stale and drops it. See `FrameSource.isCurrent(_:)`.
    public let runID: UInt64
    /// Monotonically increasing within one frame-source lifetime.
    public let sequenceNumber: UInt64
    /// Monotonic seconds from the source presentation clock. Never wall-clock time.
    public let timestamp: TimeInterval
    /// Pixel dimensions and the transform already applied at the source boundary.
    public let geometry: FrameGeometry
    /// Source-specific, independently owned frame storage.
    public let content: Content

    /// Creates a frame whose geometry already matches the upright displayed image.
    public init(
        runID: UInt64 = 0,
        sequenceNumber: UInt64,
        timestamp: TimeInterval,
        geometry: FrameGeometry,
        content: Content
    ) {
        self.runID = runID
        self.sequenceNumber = sequenceNumber
        self.timestamp = timestamp
        self.geometry = geometry
        self.content = content
    }

    /// Returns the same frame stamped with a different run.
    ///
    /// Used by sources that emit pre-built frames, so a replayed frame carries the
    /// run that actually delivered it rather than the run it was recorded in.
    public func stamped(runID: UInt64) -> SceneFrame<Content> {
        SceneFrame(
            runID: runID,
            sequenceNumber: sequenceNumber,
            timestamp: timestamp,
            geometry: geometry,
            content: content
        )
    }
}

extension SceneFrame: Equatable where Content: Equatable {}

/// Supplies live or recorded frames without exposing capture-framework details.
///
/// `frames` has one consumer and a newest-frame buffer of one. A slow consumer sees
/// the freshest available frame rather than accumulating stale guidance work.
/// `start()` and `stop()` are idempotent; stopping pauses delivery without terminating
/// the stream so a lifecycle interruption can restart the same source.
public protocol FrameSource<FrameContent>: Sendable {
    /// The independently owned payload carried by each frame.
    associatedtype FrameContent: Sendable

    /// A single-consumer stream buffered with a latest-frame capacity of one.
    var frames: AsyncStream<SceneFrame<FrameContent>> { get }

    /// The run currently delivering frames.
    ///
    /// Increments every time delivery resumes, so a consumer can tell a live frame
    /// from one buffered before the last stop.
    var currentRunID: UInt64 { get async }

    /// Begins or resumes delivery without creating a duplicate capture pipeline.
    func start() async throws
    /// Pauses delivery without terminating `frames`.
    func stop() async
}

public extension FrameSource {
    /// Whether a frame belongs to the run that is delivering now.
    ///
    /// A stream buffered with a capacity of one can hand a consumer a frame captured
    /// before the source stopped, and the producer has no way to withdraw it. Every
    /// consumer must therefore drop what this rejects:
    ///
    /// ```swift
    /// for await frame in source.frames {
    ///     guard await source.isCurrent(frame) else { continue }
    ///     …
    /// }
    /// ```
    ///
    /// Racing against a restart is safe in the only direction that matters: reading a
    /// newer run discards one live frame, whereas the reverse would admit a stale one.
    func isCurrent(_ frame: SceneFrame<FrameContent>) async -> Bool {
        await frame.runID == currentRunID
    }
}

/// Converts one captured or recorded frame into platform-neutral scene state.
///
/// The content type binds an analyzer to a compatible source at the composition
/// root without allowing a platform image framework to leak into `ForgeCore`.
public protocol SceneAnalyzer<FrameContent>: Sendable {
    /// The frame payload this analyzer understands.
    associatedtype FrameContent: Sendable

    /// Produces portable scene state, optionally using the previous state for tracking.
    func analyze(
        _ frame: SceneFrame<FrameContent>,
        previous: SceneState?
    ) async -> SceneState
}
