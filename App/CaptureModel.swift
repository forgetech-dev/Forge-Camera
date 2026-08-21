import ForgeBridge
import ForgeCapture
import ForgeCore
import ForgeFrame
import ForgeVision
import Foundation
import Observation

enum DirectorDevelopmentStatus: Sendable, Equatable {
    case disabled
    case checking
    case connected
    case analyzing
    case planReceived
    case planFailed
    case unavailable
}

/// The composition root for live capture.
///
/// This is the one place concrete types are chosen and wired together: an AVFoundation
/// frame source, a Vision analyzer, and the offline heuristic director. Everything
/// below this point talks to protocols, which is what lets the same pipeline run on a
/// recorded session in a test.
///
/// The planning pipeline deliberately remains on the local heuristic in this slice.
/// The optional HTTP client sends one bounded planning frame only after an explicit
/// user action and stores the validated result for presentation. It does not alter the
/// typed live-guidance pipeline yet.
@MainActor
@Observable
final class CaptureModel {
    private(set) var guidance = GuidanceState.idle()
    private(set) var status = CaptureStatus.idle
    private(set) var directorStatus = DirectorDevelopmentStatus.disabled
    private(set) var directorPlan: CompositionPlan?
    private(set) var frameGeometry: FrameGeometry?
    /// Frames analyzed and frames rejected as stale, for the diagnostics readout.
    private(set) var framesAnalyzed = 0

    let source: AVFoundationFrameSource

    private let pipeline: CapturePipeline<AVFoundationFrameSource, VisionSceneAnalyzer>
    private let directorClient: DirectorHTTPClient?
    private var pipelineTask: Task<Void, Never>?
    private var updatesTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    private var directorHealthTask: Task<Void, Never>?
    private var directorPlanTask: Task<Void, Never>?

    init() {
        let source = AVFoundationFrameSource()
        self.source = source
        pipeline = CapturePipeline(
            source: source,
            analyzer: VisionSceneAnalyzer(),
            director: HeuristicDirector()
        )
        directorClient = Self.configuredDirectorClient()
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
                frameGeometry = update.scene.frame
                framesAnalyzed += 1
            }
        }

        pipelineTask = Task { [weak self] in
            guard let self else { return }
            // A start failure is already published on the status stream, which is what
            // the UI shows. Rethrowing here would only crash a detached task.
            try? await pipeline.run()
        }

        startDirectorHealthCheck()
    }

    func stop() {
        pipelineTask?.cancel()
        updatesTask?.cancel()
        statusTask?.cancel()
        directorHealthTask?.cancel()
        directorPlanTask?.cancel()
        pipelineTask = nil
        updatesTask = nil
        statusTask = nil
        directorHealthTask = nil
        directorPlanTask = nil
        Task { await pipeline.stop() }
    }

    func replan() {
        Task { await pipeline.requestReplan() }
    }

    var canRequestDirectorPlan: Bool {
        guard directorPlanTask == nil else { return false }
        guard case .running = status else { return false }
        return switch directorStatus {
        case .connected, .planReceived, .planFailed:
            true
        case .disabled, .checking, .analyzing, .unavailable:
            false
        }
    }

    func requestDirectorPlan() {
        guard canRequestDirectorPlan, let directorClient else { return }

        directorStatus = .analyzing
        directorPlanTask = Task { [weak self] in
            guard let self else { return }
            defer { directorPlanTask = nil }
            do {
                guard let frame = await source.nextPlanningFrame() else {
                    directorStatus = .planFailed
                    return
                }
                let jpegData = try await Task.detached(priority: .userInitiated) {
                    try PlanningImageEncoder().encode(frame)
                }.value
                let plan = try await directorClient.plan(jpegData: jpegData)
                guard !Task.isCancelled else { return }
                directorPlan = plan
                directorStatus = .planReceived
            } catch {
                guard !Task.isCancelled else { return }
                directorStatus = .planFailed
            }
        }
    }

    private func startDirectorHealthCheck() {
        guard directorHealthTask == nil else { return }
        guard let directorClient else {
            directorStatus = .disabled
            return
        }

        directorStatus = .checking
        directorHealthTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await directorClient.checkHealth()
                guard !Task.isCancelled else { return }
                directorStatus = .connected
            } catch {
                guard !Task.isCancelled else { return }
                directorStatus = .unavailable
            }
        }
    }

    private static func configuredDirectorClient() -> DirectorHTTPClient? {
        guard let value = Bundle.main.object(
            forInfoDictionaryKey: "ForgeDirectorBaseURL"
        ) as? String,
            !value.contains("$("),
            let url = URL(string: value),
            url.host?.isEmpty == false
        else {
            return nil
        }
        return DirectorHTTPClient(baseURL: url)
    }
}
