import AVFoundation

public extension AVFoundationFrameSource {
    /// A preview layer driven directly by the capture session.
    ///
    /// Preview deliberately does **not** render the frame stream. Drawing frames
    /// ourselves would put a copy and a draw on the analysis path and tie preview
    /// latency to how fast analysis runs. The session feeds the preview layer and the
    /// video output independently, which is what keeps the viewfinder responsive when
    /// perception falls behind — and a frozen preview is a broken product in a way
    /// that a skipped analysis frame is not.
    ///
    /// The session itself stays private; only this layer escapes.
    func makePreviewLayer() -> AVCaptureVideoPreviewLayer {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        return layer
    }
}
