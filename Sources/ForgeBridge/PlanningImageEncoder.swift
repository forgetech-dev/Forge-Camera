import CoreImage
import ForgeFrame
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Failures while reducing a live frame to the bounded planning-image payload.
public enum PlanningImageEncodingError: Error, Sendable, Equatable {
    case imageCreationFailed
    case destinationCreationFailed
    case encodingFailed
}

/// Produces the one metadata-free JPEG allowed to cross the Director boundary.
public struct PlanningImageEncoder: Sendable {
    /// Maximum width or height sent from the phone.
    public static let maximumPixelDimension = 1024
    /// Deliberately below capture quality: the Director needs composition, not final pixels.
    public static let jpegQuality = 0.78

    /// Creates a stateless planning-image encoder.
    public init() {}

    /// Downscales one owned camera frame and re-encodes decoded pixels without source metadata.
    public func encode(_ frame: PixelBufferFrame) throws -> Data {
        let input = CIImage(cvPixelBuffer: frame.pixelBuffer)
        let longestEdge = max(input.extent.width, input.extent.height)
        let scale = min(1, CGFloat(Self.maximumPixelDimension) / longestEdge)
        let image = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext(options: [.cacheIntermediates: false])
        guard let rendered = context.createCGImage(image, from: image.extent) else {
            throw PlanningImageEncodingError.imageCreationFailed
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw PlanningImageEncodingError.destinationCreationFailed
        }
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: Self.jpegQuality,
        ]
        CGImageDestinationAddImage(destination, rendered, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw PlanningImageEncodingError.encodingFailed
        }
        return output as Data
    }
}
