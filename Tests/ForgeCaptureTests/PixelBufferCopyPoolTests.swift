import CoreVideo
import Testing
@testable import ForgeCapture
@testable import ForgeFrame

@Suite("Pixel-buffer copy pool")
struct PixelBufferCopyPoolTests {
    @Test("A delivered frame remains unchanged when the capture buffer is reused")
    func copyOwnsIndependentStorage() throws {
        let source = try makePixelBuffer()
        try fill(source, luma: 0x21, chroma: 0x43)
        let copy = try PixelBufferCopyPool().copy(source)

        #expect(source !== copy.pixelBuffer)
        try fill(source, luma: 0xBA, chroma: 0xDC)

        #expect(try allBytes(in: copy.pixelBuffer, plane: 0, equal: 0x21))
        #expect(try allBytes(in: copy.pixelBuffer, plane: 1, equal: 0x43))
    }

    @Test("Three retained frames exhaust the pool until one is released")
    func retainedFramesBoundPoolAllocation() throws {
        let source = try makePixelBuffer()
        let pool = PixelBufferCopyPool(maximumBufferCount: 3)
        var first: PixelBufferFrame? = try pool.copy(source)
        let second = try pool.copy(source)
        let third = try pool.copy(source)

        // The expectation is deliberately outside `withExtendedLifetime`, with an
        // empty-body call afterwards keeping all three frames alive across it.
        //
        // Wrapping the expectation instead makes the closure's result the value of
        // `#expect(throws:)`, which is Void under Swift 6.0 but not under 6.1 — so
        // `_ =` is "redundant" to one compiler and required by the other, and there
        // is no spelling that satisfies both. This form has no result to argue about,
        // and matches the idiom used below.
        #expect(throws: PixelBufferCopyError.poolExhausted) {
            try pool.copy(source)
        }
        withExtendedLifetime((first, second, third)) {}

        first = nil
        let recycled = try pool.copy(source)
        #expect(CVPixelBufferGetPixelFormatType(recycled.pixelBuffer)
            == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
        withExtendedLifetime((second, third, recycled)) {}
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
            throw TestError.pixelBufferCreationFailed(status)
        }
        return pixelBuffer
    }

    private func fill(_ pixelBuffer: CVPixelBuffer, luma: UInt8, chroma: UInt8) throws {
        let status = CVPixelBufferLockBaseAddress(pixelBuffer, [])
        guard status == kCVReturnSuccess else {
            throw TestError.pixelBufferLockFailed(status)
        }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        try fill(pixelBuffer, plane: 0, byte: luma)
        try fill(pixelBuffer, plane: 1, byte: chroma)
    }

    private func fill(_ pixelBuffer: CVPixelBuffer, plane: Int, byte: UInt8) throws {
        guard let baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, plane) else {
            throw TestError.missingBaseAddress(plane)
        }
        let byteCount = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, plane)
            * CVPixelBufferGetHeightOfPlane(pixelBuffer, plane)
        memset(baseAddress, Int32(byte), byteCount)
    }

    private func allBytes(
        in pixelBuffer: CVPixelBuffer,
        plane: Int,
        equal expected: UInt8
    ) throws -> Bool {
        let status = CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        guard status == kCVReturnSuccess else {
            throw TestError.pixelBufferLockFailed(status)
        }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, plane) else {
            throw TestError.missingBaseAddress(plane)
        }
        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, plane)
        let logicalBytesPerRow = CVPixelBufferGetWidthOfPlane(pixelBuffer, plane)
            * (plane == 0 ? 1 : 2)
        let rowCount = CVPixelBufferGetHeightOfPlane(pixelBuffer, plane)
        return (0 ..< rowCount).allSatisfy { row in
            (0 ..< logicalBytesPerRow).allSatisfy { column in
                bytes[row * bytesPerRow + column] == expected
            }
        }
    }
}

private enum TestError: Error {
    case pixelBufferCreationFailed(CVReturn)
    case pixelBufferLockFailed(CVReturn)
    case missingBaseAddress(Int)
}
