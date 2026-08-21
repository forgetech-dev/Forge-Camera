import AVFoundation
import ForgeCore
import ForgeFrame
import OSLog
#if os(iOS)
    import UIKit
#endif

/// Native phone-camera frames backed by an `AVCaptureSession`.
///
/// The session graph and lifecycle state are confined to `sessionQueue`; sample
/// delivery and its copy pool are confined to the separate serial `videoQueue`.
/// This queue confinement is the invariant behind `@unchecked Sendable`—the class
/// never exposes either mutable AVFoundation object.
public final class AVFoundationFrameSource: FrameSource, @unchecked Sendable {
    public typealias FrameContent = PixelBufferFrame

    /// Owned, orientation-corrected frames with newest-one buffering.
    public let frames: AsyncStream<SceneFrame<PixelBufferFrame>>
    /// Lifecycle state for a camera HUD or recovery screen. This stream has one consumer.
    public let statuses: AsyncStream<CaptureStatus>
    /// Applied zoom state for the camera HUD. This stream has one consumer.
    public let zoomStates: AsyncStream<CameraZoomState>

    /// The run currently delivering frames. Read from `videoQueue`, which owns it.
    public var currentRunID: UInt64 {
        get async {
            await withCheckedContinuation { continuation in
                videoQueue.async { [self] in
                    continuation.resume(returning: frameDelivery.currentRunID)
                }
            }
        }
    }

    static let logger = Logger(
        subsystem: "dev.forge.photographer",
        category: "capture"
    )

    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    let photoOutput = AVCapturePhotoOutput()
    let sessionQueue = DispatchQueue(label: "dev.forge.photographer.capture.session")
    let videoQueue = DispatchQueue(label: "dev.forge.photographer.capture.video")
    let frameDelivery: VideoFrameDelivery
    let statusContinuation: AsyncStream<CaptureStatus>.Continuation
    let zoomContinuation: AsyncStream<CameraZoomState>.Continuation
    private let applicationIsBackgrounded: @Sendable () async -> Bool
    private let authorization: any CameraAuthorization

    // Accessed only on sessionQueue after initialization.
    var isConfigured = false
    var requestedRunning = false
    var lifecycleGeneration: UInt64 = 0
    private var nextStartWaiterID: UInt64 = 0
    var startWaiters: Set<UInt64> = []
    var hasCompletedStart = false
    var isApplicationInBackground = false
    var stoppedForBackground = false
    var attemptedRuntimeRestart = false
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    var photoCaptureProcessor: PhotoCaptureProcessor?
    var notificationObservers: [NSObjectProtocol] = []
    /// Active input device. Accessed only on `sessionQueue` after initialization.
    var activeVideoDevice: AVCaptureDevice?

    /// Creates an idle source without requesting permission or starting camera hardware.
    public convenience init() {
        self.init(
            authorization: SystemCameraAuthorization(),
            applicationIsBackgrounded: {
                #if os(iOS)
                    await MainActor.run {
                        UIApplication.shared.applicationState == .background
                    }
                #else
                    false
                #endif
            }
        )
    }

    init(
        authorization: any CameraAuthorization,
        applicationIsBackgrounded: @escaping @Sendable () async -> Bool
    ) {
        self.authorization = authorization
        self.applicationIsBackgrounded = applicationIsBackgrounded
        let frameChannel = AsyncStream<SceneFrame<PixelBufferFrame>>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        frames = frameChannel.stream
        frameDelivery = VideoFrameDelivery(continuation: frameChannel.continuation)

        let statusChannel = AsyncStream<CaptureStatus>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        statuses = statusChannel.stream
        statusContinuation = statusChannel.continuation
        statusContinuation.yield(.idle)

        let zoomChannel = AsyncStream<CameraZoomState>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        zoomStates = zoomChannel.stream
        zoomContinuation = zoomChannel.continuation

        installSessionObservers()
        installApplicationObservers()
    }

    deinit {
        videoOutput.setSampleBufferDelegate(nil, queue: nil)
        rotationObservation?.invalidate()
        notificationObservers.forEach(NotificationCenter.default.removeObserver)
        frameDelivery.finish()
        statusContinuation.finish()
        zoomContinuation.finish()
    }

    /// Requests permission when needed, configures the session, and begins frame delivery.
    public func start() async throws {
        guard let request = await registerStartRequest() else { return }
        do {
            try Task.checkCancellation()
            try await authorizeCamera(for: request.generation)
            try Task.checkCancellation()
            try await startSession(for: request.generation)
            try Task.checkCancellation()
            guard await completeStartRequest(request) else {
                throw CancellationError()
            }
        } catch is CancellationError {
            await cancelStartRequest(request)
            throw CancellationError()
        } catch let error as CaptureError {
            await failStartRequest(request, error: error)
            throw error
        } catch {
            await failStartRequest(request, error: .runtimeFailure)
            throw CaptureError.runtimeFailure
        }
    }

    /// Stops capture and cancels any pending start while keeping both streams reusable.
    public func stop() async {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [self] in
                lifecycleGeneration &+= 1
                requestedRunning = false
                startWaiters.removeAll()
                hasCompletedStart = false
                stoppedForBackground = false
                attemptedRuntimeRestart = false
                stopSessionAndDeactivateDelivery()
                statusContinuation.yield(.idle)
                continuation.resume()
            }
        }
    }
}

private extension AVFoundationFrameSource {
    private struct StartRequest: Sendable {
        let generation: UInt64
        let waiterID: UInt64
    }

    private func registerStartRequest() async -> StartRequest? {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [self] in
                if requestedRunning, session.isRunning {
                    hasCompletedStart = true
                    continuation.resume(returning: nil)
                    return
                }
                if !requestedRunning || startWaiters.isEmpty {
                    lifecycleGeneration &+= 1
                    requestedRunning = true
                    startWaiters.removeAll()
                    hasCompletedStart = false
                }
                let waiterID = nextStartWaiterID
                nextStartWaiterID &+= 1
                startWaiters.insert(waiterID)
                continuation.resume(returning: StartRequest(
                    generation: lifecycleGeneration,
                    waiterID: waiterID
                ))
            }
        }
    }

    private func completeStartRequest(_ request: StartRequest) async -> Bool {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [self] in
                if lifecycleGeneration == request.generation,
                   startWaiters.remove(request.waiterID) != nil {
                    hasCompletedStart = true
                    continuation.resume(returning: true)
                } else {
                    continuation.resume(returning: false)
                }
            }
        }
    }

    private func cancelStartRequest(_ request: StartRequest) async {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [self] in
                guard lifecycleGeneration == request.generation,
                      startWaiters.remove(request.waiterID) != nil
                else {
                    continuation.resume()
                    return
                }
                if startWaiters.isEmpty, !hasCompletedStart {
                    lifecycleGeneration &+= 1
                    requestedRunning = false
                    stopSessionAndDeactivateDelivery()
                    let status: CaptureStatus = isApplicationInBackground
                        ? .interrupted(.background)
                        : .idle
                    statusContinuation.yield(status)
                }
                continuation.resume()
            }
        }
    }

    /// Invalidates every waiter for one failed physical start attempt.
    private func failStartRequest(_ request: StartRequest, error: CaptureError) async {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [self] in
                guard lifecycleGeneration == request.generation else {
                    continuation.resume()
                    return
                }
                failCurrentAttempt(error)
                continuation.resume()
            }
        }
    }

    private func authorizeCamera(for generation: UInt64) async throws {
        guard await verifyApplicationAllowsStart(for: generation) else {
            throw CancellationError()
        }

        let status = authorization.status
        if let blocking = status.blockingError {
            throw blocking
        }
        guard status == .notDetermined else { return }

        guard await publishIfStartAllowed(.awaitingPermission, generation: generation) else {
            throw CancellationError()
        }
        let granted = await authorization.requestAccess()
        // The prompt is the longest window in a start attempt, so the caller may have
        // stopped, backgrounded, or been cancelled while it was open. Re-check before
        // acting on an answer that may now belong to an abandoned run.
        guard await verifyApplicationAllowsStart(for: generation) else {
            throw CancellationError()
        }
        guard granted else {
            throw CaptureError.permissionDenied
        }
    }

    /// Reads UIKit state as well as notifications so late-created sources cannot
    /// start after `didEnterBackground` has already been posted.
    private func verifyApplicationAllowsStart(for generation: UInt64) async -> Bool {
        let systemIsBackgrounded = await applicationIsBackgrounded()
        if systemIsBackgrounded {
            await withCheckedContinuation { continuation in
                sessionQueue.async { [self] in
                    if requestedRunning,
                       lifecycleGeneration == generation,
                       !isApplicationInBackground {
                        handleEnteredBackground()
                    }
                    continuation.resume()
                }
            }
            return false
        }
        return await publishIfStartAllowed(nil, generation: generation)
    }

    /// Checks generation and app lifecycle on sessionQueue, optionally publishing state.
    private func publishIfStartAllowed(
        _ status: CaptureStatus?,
        generation: UInt64
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [self] in
                let allowed = requestedRunning
                    && lifecycleGeneration == generation
                    && !isApplicationInBackground
                if allowed, let status {
                    statusContinuation.yield(status)
                }
                continuation.resume(returning: allowed)
            }
        }
    }

    private func startSession(for generation: UInt64) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<
            Void,
            any Error
        >) in
            sessionQueue.async { [self] in
                guard requestedRunning,
                      lifecycleGeneration == generation,
                      !isApplicationInBackground
                else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                do {
                    if !isConfigured {
                        statusContinuation.yield(.configuring)
                        try configureSession()
                    }
                    if !session.isRunning {
                        activateDelivery()
                        session.startRunning()
                    }
                    guard session.isRunning else {
                        deactivateDelivery()
                        throw CaptureError.sessionFailedToStart
                    }
                    attemptedRuntimeRestart = false
                    statusContinuation.yield(.running)
                    continuation.resume()
                } catch {
                    if lifecycleGeneration == generation,
                       let captureError = error as? CaptureError {
                        // End the physical attempt before resuming its caller. A queued
                        // concurrent start can then only observe the new generation.
                        failCurrentAttempt(captureError)
                    } else if lifecycleGeneration == generation {
                        failCurrentAttempt(.runtimeFailure)
                    }
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private extension AVFoundationFrameSource {
    /// Configures the complete graph as one transaction. sessionQueue only.
    private func configureSession() throws {
        session.beginConfiguration()
        var succeeded = false
        defer {
            if !succeeded {
                session.inputs.forEach(session.removeInput)
                session.outputs.forEach(session.removeOutput)
                videoOutput.setSampleBufferDelegate(nil, queue: nil)
                activeVideoDevice = nil
            }
            session.commitConfiguration()
        }

        #if os(iOS)
            session.automaticallyConfiguresApplicationAudioSession = false
        #endif

        guard session.canSetSessionPreset(.hd1920x1080) else {
            throw CaptureError.sessionPresetUnavailable
        }
        session.sessionPreset = .hd1920x1080

        guard let device = defaultVideoDevice() else {
            throw CaptureError.cameraUnavailable
        }
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw CaptureError.deviceInputCreationFailed
        }
        guard session.canAddInput(input) else {
            throw CaptureError.deviceInputUnavailable
        }
        session.addInput(input)

        try configureVideoOutput(for: device)
        configurePhotoOutput()
        installRotationCoordinator(device: device)

        activeVideoDevice = device
        #if os(iOS)
            zoomContinuation.yield(zoomState(for: device))
        #endif
        isConfigured = true
        succeeded = true
    }

    private func configureVideoOutput(for device: AVCaptureDevice) throws {
        let pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        guard videoOutput.availableVideoPixelFormatTypes.contains(pixelFormat) else {
            throw CaptureError.videoPixelFormatUnavailable
        }
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        #if os(iOS)
            videoOutput.automaticallyConfiguresOutputBufferDimensions = false
            videoOutput.deliversPreviewSizedOutputBuffers = false
        #endif
        videoOutput.setSampleBufferDelegate(frameDelivery, queue: videoQueue)

        guard session.canAddOutput(videoOutput) else {
            throw CaptureError.videoOutputUnavailable
        }
        session.addOutput(videoOutput)

        guard let connection = videoOutput.connection(with: .video) else {
            throw CaptureError.videoConnectionUnavailable
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
        #if os(iOS)
            if connection.isCameraIntrinsicMatrixDeliverySupported {
                connection.isCameraIntrinsicMatrixDeliveryEnabled = true
            }
        #endif
    }

    private func defaultVideoDevice() -> AVCaptureDevice? {
        #if os(iOS)
            AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        #else
            AVCaptureDevice.default(for: .video)
        #endif
    }
}

private extension AVFoundationFrameSource {
    private func installRotationCoordinator(device: AVCaptureDevice) {
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        rotationCoordinator = coordinator
        // Apply the initial angle while the session is still inside its configuration
        // transaction. Video-data outputs rotate pixels physically, and setting this
        // after startRunning() forces an expensive render-pipeline reconfiguration.
        applyRotation(coordinator.videoRotationAngleForHorizonLevelCapture)
        rotationObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelCapture,
            options: [.new]
        ) { [weak self] coordinator, _ in
            guard let source = self else { return }
            let angle = coordinator.videoRotationAngleForHorizonLevelCapture
            source.sessionQueue.async {
                source.applyRotation(angle)
            }
        }
    }

    /// Looks up the connection on its owning queue instead of sending it across queues.
    private func applyRotation(_ angle: CGFloat) {
        if let photoConnection = photoOutput.connection(with: .video),
           photoConnection.isVideoRotationAngleSupported(angle) {
            photoConnection.videoRotationAngle = angle
        }

        guard let connection = videoOutput.connection(with: .video),
              connection.isVideoRotationAngleSupported(angle)
        else {
            return
        }
        // Drain and suppress the transition window. A frame captured while the
        // connection is reconfiguring must not be labelled with the old transform.
        deactivateDelivery()
        connection.videoRotationAngle = angle
        let mirrored = connection.isVideoMirrored
        let shouldActivate = requestedRunning
            && session.isRunning
            && !isApplicationInBackground
        videoQueue.sync {
            frameDelivery.updateTransform(rotationAngle: angle, mirrored: mirrored)
            if shouldActivate {
                frameDelivery.activate()
            }
        }
    }
}
