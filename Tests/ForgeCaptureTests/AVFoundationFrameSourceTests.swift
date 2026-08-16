import Testing
@testable import ForgeCapture

@Suite("AVFoundation frame source")
struct AVFoundationFrameSourceTests {
    @Test("Construction is hardware-free and begins idle")
    func constructionDoesNotStartCamera() async {
        let source = AVFoundationFrameSource()
        var statuses = source.statuses.makeAsyncIterator()

        #expect(await statuses.next() == .idle)

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
            .sessionFailedToStart,
            .runtimeFailure,
        ]

        #expect(errors.allSatisfy { $0.recoverySuggestion?.isEmpty == false })
    }
}
