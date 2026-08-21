import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ForgeDirectorCodex

@Suite("Planning image privacy sanitizer")
struct PlanningImageSanitizerTests {
    @Test("Re-encoding produces JPEG pixels without source GPS metadata")
    func stripsSourceMetadata() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "forge-sanitizer-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("source.jpg")
        let sanitizedURL = directory.appendingPathComponent("sanitized.jpg")
        try writeJPEGWithGPSMetadata(to: sourceURL)
        #expect(try gpsMetadata(in: sourceURL) != nil)

        try PlanningImageSanitizer.sanitize(sourceURL, to: sanitizedURL)

        let sanitizedSource = try #require(CGImageSourceCreateWithURL(sanitizedURL as CFURL, nil))
        #expect(CGImageSourceGetType(sanitizedSource) as String? == UTType.jpeg.identifier)
        #expect(try gpsMetadata(in: sanitizedURL) == nil)
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(
            sanitizedSource,
            0,
            nil
        ) as? [CFString: Any])
        let width = try #require(properties[kCGImagePropertyPixelWidth] as? Int)
        let height = try #require(properties[kCGImagePropertyPixelHeight] as? Int)
        #expect(max(width, height) <= PlanningImageSanitizer.maximumPixelDimension)
    }
}

private extension PlanningImageSanitizerTests {
    func writeJPEGWithGPSMetadata(to url: URL) throws {
        let png = try #require(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ))
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let destination = try #require(CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ))
        let gps: [CFString: Any] = [
            kCGImagePropertyGPSLatitude: 37.0,
            kCGImagePropertyGPSLatitudeRef: "N",
            kCGImagePropertyGPSLongitude: 122.0,
            kCGImagePropertyGPSLongitudeRef: "W",
        ]
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImagePropertyGPSDictionary: gps] as CFDictionary
        )
        #expect(CGImageDestinationFinalize(destination))
    }

    func gpsMetadata(in url: URL) throws -> [CFString: Any]? {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(
            source,
            0,
            nil
        ) as? [CFString: Any])
        return properties[kCGImagePropertyGPSDictionary] as? [CFString: Any]
    }
}
