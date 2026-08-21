import CoreVideo
import Foundation
import ImageIO
import Testing
@testable import ForgeBridge
@testable import ForgeFrame

@Suite("Planning image encoder")
struct PlanningImageEncoderTests {
    @Test("A camera frame becomes a bounded JPEG without source metadata")
    func boundedMetadataFreeJPEG() throws {
        let pixels = try makePixelBuffer(width: 1200, height: 600)
        let encoded = try PlanningImageEncoder().encode(PixelBufferFrame(pixelBuffer: pixels))
        let source = try #require(CGImageSourceCreateWithData(encoded as CFData, nil))
        let properties = try #require(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )

        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 1024)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == 512)
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
    }
}

private func makePixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
    let attributes = [
        kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary,
    ] as CFDictionary
    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_32BGRA,
        attributes,
        &pixelBuffer
    )
    guard status == kCVReturnSuccess, let pixelBuffer else {
        throw PlanningImageTestError.pixelBufferCreationFailed(status)
    }

    let lockStatus = CVPixelBufferLockBaseAddress(pixelBuffer, [])
    guard lockStatus == kCVReturnSuccess else {
        throw PlanningImageTestError.pixelBufferLockFailed(lockStatus)
    }
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
        throw PlanningImageTestError.missingBaseAddress
    }
    memset(baseAddress, 0x80, CVPixelBufferGetDataSize(pixelBuffer))
    return pixelBuffer
}

private enum PlanningImageTestError: Error {
    case pixelBufferCreationFailed(CVReturn)
    case pixelBufferLockFailed(CVReturn)
    case missingBaseAddress
}
