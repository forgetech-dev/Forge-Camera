import CoreVideo
import ForgeFrame
import Foundation

enum PixelBufferCopyError: Error, Sendable, Equatable {
    case unsupportedPixelFormat(OSType)
    case invalidPlaneLayout
    case poolCreationFailed(CVReturn)
    case poolExhausted
    case bufferAllocationFailed(CVReturn)
    case sourceLockFailed(CVReturn)
    case destinationLockFailed(CVReturn)
    case missingBaseAddress(plane: Int)
}

/// Copies borrowed capture buffers into a small, reusable pool of owned buffers.
///
/// The source invokes this object only on its serial video-delivery queue. The pool's
/// allocation threshold is a second back-pressure boundary after AVFoundation's late
/// frame dropping and the frame stream's newest-one buffer.
final class PixelBufferCopyPool {
    private struct Descriptor: Equatable {
        let width: Int
        let height: Int
        let pixelFormat: OSType
    }

    private let maximumBufferCount: Int
    private var descriptor: Descriptor?
    private var pool: CVPixelBufferPool?

    init(maximumBufferCount: Int = 3) {
        precondition(maximumBufferCount > 0, "A pixel-buffer pool needs positive capacity")
        self.maximumBufferCount = maximumBufferCount
    }

    func copy(
        _ source: CVPixelBuffer,
        cameraIntrinsics: CameraIntrinsics? = nil
    ) throws -> PixelBufferFrame {
        let sourceDescriptor = Descriptor(
            width: CVPixelBufferGetWidth(source),
            height: CVPixelBufferGetHeight(source),
            pixelFormat: CVPixelBufferGetPixelFormatType(source)
        )
        guard sourceDescriptor.pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange else {
            throw PixelBufferCopyError.unsupportedPixelFormat(sourceDescriptor.pixelFormat)
        }
        guard CVPixelBufferGetPlaneCount(source) == 2 else {
            throw PixelBufferCopyError.invalidPlaneLayout
        }

        if descriptor != sourceDescriptor {
            pool = try makePool(for: sourceDescriptor)
            descriptor = sourceDescriptor
        }
        guard let pool else {
            throw PixelBufferCopyError.poolCreationFailed(kCVReturnPoolAllocationFailed)
        }

        let destination = try allocateBuffer(from: pool)
        try copyPlanes(from: source, to: destination)
        CVBufferPropagateAttachments(source, destination)
        return PixelBufferFrame(
            pixelBuffer: destination,
            cameraIntrinsics: cameraIntrinsics
        )
    }

    private func makePool(for descriptor: Descriptor) throws -> CVPixelBufferPool {
        let poolAttributes = [
            kCVPixelBufferPoolMinimumBufferCountKey as String: maximumBufferCount,
        ] as CFDictionary
        let pixelBufferAttributes = [
            kCVPixelBufferWidthKey as String: descriptor.width,
            kCVPixelBufferHeightKey as String: descriptor.height,
            kCVPixelBufferPixelFormatTypeKey as String: descriptor.pixelFormat,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary,
        ] as CFDictionary

        var newPool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            poolAttributes,
            pixelBufferAttributes,
            &newPool
        )
        guard status == kCVReturnSuccess, let newPool else {
            throw PixelBufferCopyError.poolCreationFailed(status)
        }
        return newPool
    }

    private func allocateBuffer(from pool: CVPixelBufferPool) throws -> CVPixelBuffer {
        let allocationAttributes = [
            kCVPixelBufferPoolAllocationThresholdKey as String: maximumBufferCount,
        ] as CFDictionary
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(
            kCFAllocatorDefault,
            pool,
            allocationAttributes,
            &pixelBuffer
        )

        if status == kCVReturnWouldExceedAllocationThreshold {
            throw PixelBufferCopyError.poolExhausted
        }
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw PixelBufferCopyError.bufferAllocationFailed(status)
        }
        return pixelBuffer
    }

    private func copyPlanes(from source: CVPixelBuffer, to destination: CVPixelBuffer) throws {
        guard CVPixelBufferGetPlaneCount(destination) == 2 else {
            throw PixelBufferCopyError.invalidPlaneLayout
        }

        let sourceLockStatus = CVPixelBufferLockBaseAddress(source, .readOnly)
        guard sourceLockStatus == kCVReturnSuccess else {
            throw PixelBufferCopyError.sourceLockFailed(sourceLockStatus)
        }
        defer { CVPixelBufferUnlockBaseAddress(source, .readOnly) }

        let destinationLockStatus = CVPixelBufferLockBaseAddress(destination, [])
        guard destinationLockStatus == kCVReturnSuccess else {
            throw PixelBufferCopyError.destinationLockFailed(destinationLockStatus)
        }
        defer { CVPixelBufferUnlockBaseAddress(destination, []) }

        for plane in 0 ..< 2 {
            guard CVPixelBufferGetWidthOfPlane(source, plane)
                == CVPixelBufferGetWidthOfPlane(destination, plane),
                CVPixelBufferGetHeightOfPlane(source, plane)
                == CVPixelBufferGetHeightOfPlane(destination, plane)
            else {
                throw PixelBufferCopyError.invalidPlaneLayout
            }
            guard let sourceBaseAddress = CVPixelBufferGetBaseAddressOfPlane(source, plane),
                  let destinationBaseAddress = CVPixelBufferGetBaseAddressOfPlane(
                      destination,
                      plane
                  )
            else {
                throw PixelBufferCopyError.missingBaseAddress(plane: plane)
            }

            let sourceBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(source, plane)
            let destinationBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(destination, plane)
            let copiedBytesPerRow = min(sourceBytesPerRow, destinationBytesPerRow)
            let rowCount = CVPixelBufferGetHeightOfPlane(source, plane)

            for row in 0 ..< rowCount {
                memcpy(
                    destinationBaseAddress.advanced(by: row * destinationBytesPerRow),
                    sourceBaseAddress.advanced(by: row * sourceBytesPerRow),
                    copiedBytesPerRow
                )
            }
        }
    }
}
