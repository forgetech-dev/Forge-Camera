import Testing
@testable import ForgeCapture

@Suite("AVFoundation frame source")
struct AVFoundationFrameSourceTests {
    @Test("Camera zoom clamps requests to the supported interactive range")
    func cameraZoomClampsRequests() {
        let state = CameraZoomState(
            factor: 2,
            deviceMinimumFactor: 1,
            deviceMaximumFactor: 6
        )

        #expect(state.clampedFactor(0.5) == 1)
        #expect(state.clampedFactor(3.5) == 3.5)
        #expect(state.clampedFactor(12) == 6)
        #expect(state.clampedFactor(.infinity) == 1)
    }

    @Test("Interactive zoom has a deliberate quality ceiling")
    func cameraZoomUsesQualityCeiling() {
        let state = CameraZoomState(
            factor: 20,
            deviceMinimumFactor: 1,
            deviceMaximumFactor: 100
        )

        #expect(state.factor == 8)
        #expect(state.maximumFactor == 8)
    }

    @Test("Construction is hardware-free and begins idle")
    func constructionDoesNotStartCamera() async {
        let source = AVFoundationFrameSource()
        var statuses = source.statuses.makeAsyncIterator()

        #expect(await statuses.next() == .idle)
        #expect(await source.isPhotoCaptureAvailable == false)
        await #expect(throws: CaptureError.photoCaptureUnavailable) {
            try await source.capturePhoto()
        }

        await source.stop()
        #expect(await statuses.next() == .idle)
    }

    @Test("A source created in the background rejects start before touching hardware")
    func backgroundStartIsRejected() async {
        let source = AVFoundationFrameSource(
            authorization: StubCameraAuthorization(status: .authorized),
            applicationIsBackgrounded: { true }
        )
        var statuses = source.statuses.makeAsyncIterator()
        #expect(await statuses.next() == .idle)

        await #expect(throws: CancellationError.self) {
            try await source.start()
        }

        #expect(await statuses.next() == .interrupted(.background))
    }

    @Test("Every capture failure carries recovery guidance")
    func errorsAreActionable() {
        let errors: [CaptureError] = [
            .permissionDenied,
            .permissionRestricted,
            .cameraUnavailable,
            .sessionPresetUnavailable,
            .videoPixelFormatUnavailable,
            .deviceInputCreationFailed,
            .deviceInputUnavailable,
            .videoOutputUnavailable,
            .videoConnectionUnavailable,
            .photoCaptureUnavailable,
            .photoCaptureInProgress,
            .photoDataUnavailable,
            .photoProcessingFailed,
            .sessionFailedToStart,
            .runtimeFailure,
        ]

        #expect(errors.allSatisfy { $0.recoverySuggestion?.isEmpty == false })
    }
}
