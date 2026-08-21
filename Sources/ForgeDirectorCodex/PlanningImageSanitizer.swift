import Foundation
import ImageIO
import UniformTypeIdentifiers

enum PlanningImageSanitizer {
    static let maximumPixelDimension = 1024
    static let jpegQuality = 0.82

    /// Re-encoding from decoded pixels prevents EXIF, GPS, and other source metadata
    /// from crossing the provider boundary. Only the new JPEG quality is specified.
    static func sanitize(_ sourceURL: URL, to destinationURL: URL) throws {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
            throw CodexDirectorSpikeError.inputImageDecodingFailed
        }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelDimension,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            thumbnailOptions as CFDictionary
        ) else {
            throw CodexDirectorSpikeError.inputImageDecodingFailed
        }
        guard let destination = CGImageDestinationCreateWithURL(
            destinationURL as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw CodexDirectorSpikeError.imageSanitizationFailed
        }
        let destinationProperties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: jpegQuality,
        ]
        CGImageDestinationAddImage(destination, image, destinationProperties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw CodexDirectorSpikeError.imageSanitizationFailed
        }
    }
}
