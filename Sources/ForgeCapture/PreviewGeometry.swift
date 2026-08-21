import ForgeCore
import Foundation

/// Maps Forge's upright normalized image space into an aspect-fill preview viewport.
///
/// `FrameGeometry` already describes orientation-corrected pixels, so rotation is not
/// applied a second time here. Preview mirroring remains explicit because it is a
/// presentation choice and may differ from the unmirrored space used for guidance.
public struct PreviewGeometry: Sendable, Equatable {
    private let renderedImageSize: CGSize
    private let renderedImageOrigin: CGPoint
    private let previewMirrored: Bool

    /// Creates a mapping for one orientation-corrected camera frame and viewport.
    ///
    /// Returns `nil` when either size has no drawable area.
    public init?(
        frame: FrameGeometry,
        viewportSize: CGSize,
        previewMirrored: Bool
    ) {
        guard frame.pixelWidth > 0,
              frame.pixelHeight > 0,
              viewportSize.width > 0,
              viewportSize.height > 0
        else {
            return nil
        }

        let imageSize = CGSize(width: frame.pixelWidth, height: frame.pixelHeight)
        let scale = max(
            viewportSize.width / imageSize.width,
            viewportSize.height / imageSize.height
        )
        renderedImageSize = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
        renderedImageOrigin = CGPoint(
            x: (viewportSize.width - renderedImageSize.width) / 2,
            y: (viewportSize.height - renderedImageSize.height) / 2
        )
        self.previewMirrored = previewMirrored
    }

    /// Converts an image-space point into preview-layer points.
    public func point(for normalizedPoint: NormalizedPoint) -> CGPoint {
        let x = previewMirrored ? 1 - normalizedPoint.x : normalizedPoint.x
        return CGPoint(
            x: renderedImageOrigin.x + x * renderedImageSize.width,
            y: renderedImageOrigin.y + normalizedPoint.y * renderedImageSize.height
        )
    }

    /// Converts an image-space rectangle into preview-layer points.
    public func rect(for normalizedRect: NormalizedRect) -> CGRect {
        let x = previewMirrored ? 1 - normalizedRect.maxX : normalizedRect.minX
        return CGRect(
            x: renderedImageOrigin.x + x * renderedImageSize.width,
            y: renderedImageOrigin.y + normalizedRect.minY * renderedImageSize.height,
            width: normalizedRect.width * renderedImageSize.width,
            height: normalizedRect.height * renderedImageSize.height
        )
    }
}
