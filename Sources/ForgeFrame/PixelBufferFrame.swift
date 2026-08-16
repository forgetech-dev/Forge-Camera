import CoreVideo
import Foundation

/// The camera calibration attachment copied from one captured sample.
package struct CameraIntrinsics: Sendable, Equatable {
    /// An owned `matrix_float3x3` representation in column-major layout.
    package let matrixData: Data

    package init(matrixData: Data) {
        self.matrixData = matrixData
    }
}

/// Immutable pixel storage shared by capture and on-device analysis.
///
/// The capture callback copies AVFoundation's borrowed buffer before creating this
/// value. Consumers may retain the copy for analysis, but must treat its pixels as
/// read-only so the same frame can safely cross concurrency domains.
///
/// `CVPixelBuffer` is explicitly non-`Sendable`. This wrapper's unchecked conformance
/// is valid because construction is package-scoped, every instance owns an independent
/// copy, and Forge never mutates that copy after publication.
public final class PixelBufferFrame: @unchecked Sendable {
    /// The owned pixel buffer. Package consumers must only read its contents.
    package let pixelBuffer: CVPixelBuffer
    /// The owned intrinsics attachment emitted for this sample, when available.
    package let cameraIntrinsics: CameraIntrinsics?

    /// Width after the capture connection has applied its rotation.
    public var pixelWidth: Int {
        CVPixelBufferGetWidth(pixelBuffer)
    }

    /// Height after the capture connection has applied its rotation.
    public var pixelHeight: Int {
        CVPixelBufferGetHeight(pixelBuffer)
    }

    package init(
        pixelBuffer: CVPixelBuffer,
        cameraIntrinsics: CameraIntrinsics? = nil
    ) {
        self.pixelBuffer = pixelBuffer
        self.cameraIntrinsics = cameraIntrinsics
    }
}
