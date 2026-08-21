import AVFoundation
import CoreMedia
import ForgeCore
import ForgeFrame
import Foundation

/// Bridges AVFoundation's borrowed sample callback into owned, newest-only frames.
///
/// AVFoundation invokes the delegate exclusively on `videoQueue`. That serial queue
/// owns the copy pool and sequence counter, which is the `@unchecked Sendable`
/// invariant. Neither a `CMSampleBuffer` nor its borrowed pixel buffer is published.
final class VideoFrameDelivery: NSObject,
    AVCaptureVideoDataOutputSampleBufferDelegate,
    @unchecked Sendable {
    private let continuation: AsyncStream<SceneFrame<PixelBufferFrame>>.Continuation
    private let copyPool = PixelBufferCopyPool()
    private var nextSequenceNumber: UInt64 = 0
    private var isActive = false
    private var appliedRotationAngle: CGFloat = 0
    private var isMirrored = false
    private var planningFrameContinuation: CheckedContinuation<PixelBufferFrame?, Never>?
    /// Identifies the current continuous run. Bumped on every activation so a frame
    /// buffered before a stop, a backgrounding, or a runtime restart is recognisable
    /// as stale once delivery resumes.
    private(set) var currentRunID: UInt64 = 0

    init(continuation: AsyncStream<SceneFrame<PixelBufferFrame>>.Continuation) {
        self.continuation = continuation
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        deliver(sampleBuffer)
    }

    func deliver(_ sampleBuffer: CMSampleBuffer) {
        guard isActive else { return }
        let sequenceNumber = nextSequenceNumber
        nextSequenceNumber += 1
        guard let borrowedBuffer = sampleBuffer.imageBuffer else { return }
        let timestamp = sampleBuffer.presentationTimeStamp.seconds
        guard timestamp.isFinite else { return }

        let pixels: PixelBufferFrame
        do {
            pixels = try copyPool.copy(
                borrowedBuffer,
                cameraIntrinsics: cameraIntrinsics(from: sampleBuffer)
            )
        } catch {
            // Pool exhaustion is intentional back-pressure; malformed buffers are
            // isolated to this frame. Neither condition should stop the preview.
            return
        }

        let frame = SceneFrame(
            runID: currentRunID,
            sequenceNumber: sequenceNumber,
            timestamp: timestamp,
            geometry: FrameGeometry(
                pixelWidth: pixels.pixelWidth,
                pixelHeight: pixels.pixelHeight,
                appliedRotation: .degrees(Double(appliedRotationAngle)),
                wasMirrored: isMirrored
            ),
            content: pixels
        )
        planningFrameContinuation?.resume(returning: pixels)
        planningFrameContinuation = nil
        _ = continuation.yield(frame)
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        recordDrop()
    }

    func recordDrop() {
        guard isActive else { return }
        // Preserve gaps so replay/metrics can distinguish camera-level drops from
        // successfully delivered frames without retaining the dropped sample.
        nextSequenceNumber += 1
    }

    func updateTransform(rotationAngle: CGFloat, mirrored: Bool) {
        appliedRotationAngle = rotationAngle
        isMirrored = mirrored
    }

    func activate() {
        // A new run starts even when resuming after an interruption: frames from
        // before the pause describe a scene the user has since moved away from.
        currentRunID &+= 1
        isActive = true
    }

    func deactivate() {
        isActive = false
        planningFrameContinuation?.resume(returning: nil)
        planningFrameContinuation = nil
    }

    func requestPlanningFrame(
        _ continuation: CheckedContinuation<PixelBufferFrame?, Never>
    ) {
        planningFrameContinuation?.resume(returning: nil)
        planningFrameContinuation = continuation
    }

    private func cameraIntrinsics(from sampleBuffer: CMSampleBuffer) -> CameraIntrinsics? {
        guard let matrixData = CMGetAttachment(
            sampleBuffer,
            key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix,
            attachmentModeOut: nil
        ) as? Data else {
            return nil
        }
        // A column-major matrix_float3x3 is stored as three padded SIMD3 columns.
        let expectedByteCount = 3 * MemoryLayout<SIMD3<Float>>.stride
        guard matrixData.count == expectedByteCount else { return nil }
        return CameraIntrinsics(matrixData: Data(matrixData))
    }

    func finish() {
        planningFrameContinuation?.resume(returning: nil)
        planningFrameContinuation = nil
        continuation.finish()
    }
}
