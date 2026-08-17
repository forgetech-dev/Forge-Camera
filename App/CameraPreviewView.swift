import AVFoundation
import ForgeCapture
import SwiftUI

/// The live viewfinder.
///
/// Backed by `AVCaptureVideoPreviewLayer`, which the capture session drives directly.
/// The frame stream is a separate consumer of the same session, so a slow analysis
/// pass cannot stall the preview — and preview stalling is the one failure a camera
/// app cannot absorb.
///
/// This wrapper stays deliberately thin: no logic, no state, just a layer sized to
/// its view.
struct CameraPreviewView: UIViewRepresentable {
    let source: AVFoundationFrameSource

    func makeUIView(context _: Context) -> PreviewLayerView {
        let view = PreviewLayerView()
        view.previewLayer = source.makePreviewLayer()
        return view
    }

    func updateUIView(_: PreviewLayerView, context _: Context) {}
}

/// A view whose backing layer is the capture preview.
///
/// Hosting the preview as the view's own layer avoids a second layer to keep in sync
/// with resizing and rotation.
final class PreviewLayerView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer? {
        didSet {
            oldValue?.removeFromSuperlayer()
            guard let previewLayer else { return }
            previewLayer.frame = bounds
            layer.addSublayer(previewLayer)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // The layer is not auto-resized by Auto Layout, so it tracks bounds here.
        previewLayer?.frame = bounds
    }
}
