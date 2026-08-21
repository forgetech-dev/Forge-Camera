import CoreMedia
import CoreVideo
import ForgeCore
import Foundation
import Testing
@testable import ForgeCapture
@testable import ForgeFrame

@Suite("Video-frame delivery")
struct VideoFrameDeliveryTests {
    @Test("A borrowed sample becomes an owned frame with its capture metadata")
    func deliveryCopiesPixelsAndMetadata() async throws {
        let channel = AsyncStream<SceneFrame<PixelBufferFrame>>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        let delivery = VideoFrameDelivery(continuation: channel.continuation)
        let source = try makePixelBuffer()
        try fill(source, luma: 0x21, chroma: 0x43)
        let intrinsics = Data((0 ..< 48).map(UInt8.init))
        let sample = try makeSampleBuffer(
            imageBuffer: source,
            timestamp: CMTime(value: 125, timescale: 100),
            intrinsics: intrinsics
        )

        delivery.updateTransform(rotationAngle: 90, mirrored: true)
        delivery.activate()
        delivery.deliver(sample)
        try fill(source, luma: 0xBA, chroma: 0xDC)

        var iterator = channel.stream.makeAsyncIterator()
        let frame = try #require(await iterator.next())
        #expect(frame.sequenceNumber == 0)
        #expect(frame.timestamp == 1.25)
        #expect(frame.geometry.pixelWidth == 16)
        #expect(frame.geometry.pixelHeight == 8)
        #expect(frame.geometry.appliedRotation == .degrees(90))
        #expect(frame.geometry.wasMirrored)
        #expect(frame.content.cameraIntrinsics?.matrixData == intrinsics)
        #expect(try firstByte(in: frame.content.pixelBuffer, plane: 0) == 0x21)
        #expect(try firstByte(in: frame.content.pixelBuffer, plane: 1) == 0x43)
        delivery.finish()
    }

    @Test("Inactive callbacks are ignored and the stream keeps the newest sequence")
    func deliveryTracksDropsAndKeepsNewestFrame() async throws {
        let channel = AsyncStream<SceneFrame<PixelBufferFrame>>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        let delivery = VideoFrameDelivery(continuation: channel.continuation)
        let source = try makePixelBuffer()
        let first = try makeSampleBuffer(imageBuffer: source, timestamp: .zero)
        let second = try makeSampleBuffer(
            imageBuffer: source,
            timestamp: CMTime(value: 1, timescale: 30)
        )

        delivery.activate()
        delivery.recordDrop()
        delivery.deactivate()
        delivery.recordDrop()
        delivery.deliver(first)
        delivery.activate()
        delivery.deliver(first)
        delivery.deliver(second)

        var iterator = channel.stream.makeAsyncIterator()
        let frame = try #require(await iterator.next())
        #expect(frame.sequenceNumber == 2)
        #expect(frame.timestamp == 1.0 / 30.0)
        delivery.finish()
    }

    @Test("A planning request receives one owned frame without consuming the analysis stream")
    func oneShotPlanningFrame() async throws {
        let channel = AsyncStream<SceneFrame<PixelBufferFrame>>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        let delivery = VideoFrameDelivery(continuation: channel.continuation)
        let source = try makePixelBuffer()
        try fill(source, luma: 0x31, chroma: 0x53)
        let sample = try makeSampleBuffer(imageBuffer: source, timestamp: .zero)

        delivery.activate()
        let planningFrame = await withCheckedContinuation { continuation in
            delivery.requestPlanningFrame(continuation)
            delivery.deliver(sample)
        }

        let plannedPixels = try #require(planningFrame)
        var iterator = channel.stream.makeAsyncIterator()
        let analysisFrame = try #require(await iterator.next())
        #expect(plannedPixels === analysisFrame.content)
        #expect(try firstByte(in: plannedPixels.pixelBuffer, plane: 0) == 0x31)
        delivery.finish()
    }

    @Test("Separate planning actions receive separate newly delivered frames")
    func repeatedPlanningFrames() async throws {
        let channel = AsyncStream<SceneFrame<PixelBufferFrame>>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        let delivery = VideoFrameDelivery(continuation: channel.continuation)
        let source = try makePixelBuffer()
        delivery.activate()

        try fill(source, luma: 0x12, chroma: 0x34)
        let firstSample = try makeSampleBuffer(imageBuffer: source, timestamp: .zero)
        let first = await withCheckedContinuation { continuation in
            delivery.requestPlanningFrame(continuation)
            delivery.deliver(firstSample)
        }

        try fill(source, luma: 0x56, chroma: 0x78)
        let secondSample = try makeSampleBuffer(
            imageBuffer: source,
            timestamp: CMTime(value: 1, timescale: 30)
        )
        let second = await withCheckedContinuation { continuation in
            delivery.requestPlanningFrame(continuation)
            delivery.deliver(secondSample)
        }

        let firstPixels = try #require(first)
        let secondPixels = try #require(second)
        #expect(firstPixels !== secondPixels)
        #expect(try firstByte(in: firstPixels.pixelBuffer, plane: 0) == 0x12)
        #expect(try firstByte(in: secondPixels.pixelBuffer, plane: 0) == 0x56)
        delivery.finish()
    }

    private func makePixelBuffer(width: Int = 16, height: Int = 8) throws -> CVPixelBuffer {
        let attributes = [
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary,
        ] as CFDictionary
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            attributes,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw VideoDeliveryTestError.pixelBufferCreationFailed(status)
        }
        return pixelBuffer
    }

    private func makeSampleBuffer(
        imageBuffer: CVPixelBuffer,
        timestamp: CMTime,
        intrinsics: Data? = nil
    ) throws -> CMSampleBuffer {
        var formatDescription: CMVideoFormatDescription?
        let descriptionStatus = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: imageBuffer,
            formatDescriptionOut: &formatDescription
        )
        guard descriptionStatus == noErr, let formatDescription else {
            throw VideoDeliveryTestError.formatDescriptionCreationFailed(descriptionStatus)
        }

        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: timestamp,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: imageBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        guard sampleStatus == noErr, let sampleBuffer else {
            throw VideoDeliveryTestError.sampleBufferCreationFailed(sampleStatus)
        }
        if let intrinsics {
            CMSetAttachment(
                sampleBuffer,
                key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix,
                value: intrinsics as CFData,
                attachmentMode: kCMAttachmentMode_ShouldPropagate
            )
        }
        return sampleBuffer
    }

    private func fill(_ pixelBuffer: CVPixelBuffer, luma: UInt8, chroma: UInt8) throws {
        let status = CVPixelBufferLockBaseAddress(pixelBuffer, [])
        guard status == kCVReturnSuccess else {
            throw VideoDeliveryTestError.pixelBufferLockFailed(status)
        }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        try fill(pixelBuffer, plane: 0, byte: luma)
        try fill(pixelBuffer, plane: 1, byte: chroma)
    }

    private func fill(_ pixelBuffer: CVPixelBuffer, plane: Int, byte: UInt8) throws {
        guard let baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, plane) else {
            throw VideoDeliveryTestError.missingBaseAddress(plane)
        }
        let byteCount = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, plane)
            * CVPixelBufferGetHeightOfPlane(pixelBuffer, plane)
        memset(baseAddress, Int32(byte), byteCount)
    }

    private func firstByte(in pixelBuffer: CVPixelBuffer, plane: Int) throws -> UInt8 {
        let status = CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        guard status == kCVReturnSuccess else {
            throw VideoDeliveryTestError.pixelBufferLockFailed(status)
        }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, plane) else {
            throw VideoDeliveryTestError.missingBaseAddress(plane)
        }
        return baseAddress.assumingMemoryBound(to: UInt8.self).pointee
    }
}

private enum VideoDeliveryTestError: Error {
    case pixelBufferCreationFailed(CVReturn)
    case formatDescriptionCreationFailed(OSStatus)
    case sampleBufferCreationFailed(OSStatus)
    case pixelBufferLockFailed(CVReturn)
    case missingBaseAddress(Int)
}
