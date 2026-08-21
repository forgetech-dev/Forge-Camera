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

enum PhotoCaptureStatus: Sendable, Equatable {
    case idle
    case capturing
    case saved
    case failed(String)
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
    private(set) var directorTargetFrame: NormalizedRect?
    private(set) var frameGeometry: FrameGeometry?
    private(set) var zoomState: CameraZoomState?
    private(set) var isPhonePhotoCaptureAvailable = false
    private(set) var photoCaptureStatus = PhotoCaptureStatus.idle
    private(set) var captureFeedbackCount = 0
    /// Frames analyzed and frames rejected as stale, for the diagnostics readout.
    private(set) var framesAnalyzed = 0

    let source: AVFoundationFrameSource

    private let analyzer: VisionSceneAnalyzer
    private let pipeline: CapturePipeline<AVFoundationFrameSource, VisionSceneAnalyzer>
    private let directorClient: DirectorHTTPClient?
    private let photoLibraryWriter = PhotoLibraryWriter()
    private var pipelineTask: Task<Void, Never>?
    private var updatesTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    private var zoomStateTask: Task<Void, Never>?
    private var directorHealthTask: Task<Void, Never>?
    private var directorPlanTask: Task<Void, Never>?
    private var photoCaptureTask: Task<Void, Never>?
    private var photoStatusResetTask: Task<Void, Never>?
    private var nextSelectionTrackingID: UInt64 = 0
    private var trackedPlanReference: TrackedPlanReference?

    private struct TrackedPlanReference {
        let id: UInt64
        let sourceRegion: NormalizedRect
        let targetFrame: NormalizedRect
    }

    init() {
        let source = AVFoundationFrameSource()
        let analyzer = VisionSceneAnalyzer()
        self.source = source
        self.analyzer = analyzer
        pipeline = CapturePipeline(
            source: source,
            analyzer: analyzer,
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
                if case .running = status {
                    isPhonePhotoCaptureAvailable = await source.isPhotoCaptureAvailable
                }
            }
        }

        zoomStateTask = Task { [weak self] in
            guard let self else { return }
            for await zoomState in source.zoomStates {
                self.zoomState = zoomState
            }
        }

        updatesTask = Task { [weak self] in
            guard let self else { return }
            for await update in pipeline.updates {
                guidance = update.guidance
                frameGeometry = update.scene.frame
                updateDirectorTargetFrame(from: update.scene.selectionTracking)
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
        zoomStateTask?.cancel()
        directorHealthTask?.cancel()
        directorPlanTask?.cancel()
        photoCaptureTask?.cancel()
        photoStatusResetTask?.cancel()
        pipelineTask = nil
        updatesTask = nil
        statusTask = nil
        zoomStateTask = nil
        directorHealthTask = nil
        directorPlanTask = nil
        photoCaptureTask = nil
        photoStatusResetTask = nil
        isPhonePhotoCaptureAvailable = false
        photoCaptureStatus = .idle
        Task {
            await pipeline.stop()
            await analyzer.clearSelectionTracking()
        }
    }

    func replan() {
        Task { await pipeline.requestReplan() }
    }

    func setZoomFactor(_ requestedFactor: Double) {
        guard let zoomState else { return }
        source.setZoomFactor(zoomState.clampedFactor(requestedFactor))
    }

    func resetZoom() {
        setZoomFactor(1)
    }

    var canCapturePhoto: Bool {
        guard isPhonePhotoCaptureAvailable, photoCaptureTask == nil else { return false }
        guard case .running = status else { return false }
        return true
    }

    func capturePhoto() {
        guard canCapturePhoto else { return }

        photoStatusResetTask?.cancel()
        photoStatusResetTask = nil
        photoCaptureStatus = .capturing
        captureFeedbackCount &+= 1
        photoCaptureTask = Task { [weak self] in
            guard let self else { return }
            defer { photoCaptureTask = nil }

            do {
                let data = try await source.capturePhoto()
                try Task.checkCancellation()
                try await photoLibraryWriter.save(data)
                try Task.checkCancellation()
                photoCaptureStatus = .saved
                schedulePhotoStatusReset()
            } catch is CancellationError {
                photoCaptureStatus = .idle
            } catch let error as CaptureError {
                photoCaptureStatus = .failed(
                    error.recoverySuggestion ?? "The photo could not be captured."
                )
            } catch let error as PhotoLibraryWriteError {
                photoCaptureStatus = .failed(error.userMessage)
            } catch {
                photoCaptureStatus = .failed("The photo could not be saved. Try again.")
            }
        }
    }

    private func schedulePhotoStatusReset() {
        photoStatusResetTask?.cancel()
        photoStatusResetTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(1.5))
            } catch {
                return
            }
            guard let self, photoCaptureStatus == .saved else { return }
            photoCaptureStatus = .idle
            photoStatusResetTask = nil
        }
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
                await configureSelectionTracking(for: plan)
                directorStatus = .planReceived
            } catch {
                guard !Task.isCancelled else { return }
                directorStatus = .planFailed
            }
        }
    }

    private func configureSelectionTracking(for plan: CompositionPlan) async {
        guard let sourceRegion = plan.selection?.sourceRegion,
              let targetFrame = plan.framing?.targetFrame
        else {
            trackedPlanReference = nil
            directorTargetFrame = plan.framing?.targetFrame
            await analyzer.clearSelectionTracking()
            return
        }

        nextSelectionTrackingID &+= 1
        let reference = TrackedPlanReference(
            id: nextSelectionTrackingID,
            sourceRegion: sourceRegion,
            targetFrame: targetFrame
        )
        trackedPlanReference = reference
        // Display the planned result immediately. The first subsequent camera frame
        // replaces it with a tracked projection or hides it if tracking cannot lock.
        directorTargetFrame = targetFrame
        await analyzer.beginSelectionTracking(id: reference.id, region: sourceRegion)
    }

    private func updateDirectorTargetFrame(
        from observation: SelectionTrackingObservation?
    ) {
        guard let reference = trackedPlanReference else { return }
        guard let observation, observation.trackingID == reference.id else { return }
        guard let trackedRegion = observation.bounds else {
            // A fixed screen-space frame after tracking is lost would be actively
            // misleading, so withhold it until the user requests a fresh analysis.
            directorTargetFrame = nil
            return
        }

        directorTargetFrame = reference.targetFrame.projected(
            from: reference.sourceRegion,
            to: trackedRegion
        )
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
