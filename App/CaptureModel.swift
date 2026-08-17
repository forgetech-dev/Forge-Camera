import ForgeCapture
import ForgeCore
import ForgeFrame
import ForgeVision
import Foundation
import Observation

/// The composition root for live capture.
///
/// This is the one place concrete types are chosen and wired together: an AVFoundation
/// frame source, a Vision analyzer, and the offline heuristic director. Everything
/// below this point talks to protocols, which is what lets the same pipeline run on a
/// recorded session in a test.
///
/// The director is deliberately the local heuristic for now. No network, no key, no
/// account — and the app is useful anyway. Swapping in a hosted provider is a one-line
/// change here and nowhere else.
@MainActor
@Observable
final class CaptureModel {
    private(set) var guidance = GuidanceState.idle()
    private(set) var status = CaptureStatus.idle
    private(set) var subjectCount = 0
    /// Frames analyzed and frames rejected as stale, for the diagnostics readout.
    private(set) var framesAnalyzed = 0

    let source: AVFoundationFrameSource

    private let pipeline: CapturePipeline<AVFoundationFrameSource, VisionSceneAnalyzer>
    private var pipelineTask: Task<Void, Never>?
    private var updatesTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?

    init() {
        let source = AVFoundationFrameSource()
        self.source = source
        pipeline = CapturePipeline(
            source: source,
            analyzer: VisionSceneAnalyzer(),
            director: HeuristicDirector()
        )
    }

    func start() {
        guard pipelineTask == nil else { return }

        statusTask = Task { [weak self] in
            guard let self else { return }
            for await status in source.statuses {
                self.status = status
            }
        }

        updatesTask = Task { [weak self] in
            guard let self else { return }
            for await update in pipeline.updates {
                guidance = update.guidance
                subjectCount = update.scene.subjects.count
                framesAnalyzed += 1
            }
        }

        pipelineTask = Task { [weak self] in
            guard let self else { return }
            // A start failure is already published on the status stream, which is what
            // the UI shows. Rethrowing here would only crash a detached task.
            try? await pipeline.run()
        }
    }

    func stop() {
        pipelineTask?.cancel()
        updatesTask?.cancel()
        statusTask?.cancel()
        pipelineTask = nil
        updatesTask = nil
        statusTask = nil
        Task { await pipeline.stop() }
    }

    func replan() {
        Task { await pipeline.requestReplan() }
    }
}
