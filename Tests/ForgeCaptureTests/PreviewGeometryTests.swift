import ForgeCore
import Foundation
import Testing
@testable import ForgeCapture

@Suite("Preview geometry")
struct PreviewGeometryTests {
    @Test("Aspect fill accounts for image content cropped outside the viewport")
    func aspectFillCropping() throws {
        let geometry = try #require(PreviewGeometry(
            frame: frame(width: 160, height: 90),
            viewportSize: CGSize(width: 100, height: 100),
            previewMirrored: false
        ))

        let rect = geometry.rect(for: NormalizedRect(
            x: 0.25,
            y: 0.1,
            width: 0.5,
            height: 0.4
        ))

        #expect(rect.minX.isApproximately(5.555_555_555_6))
        #expect(rect.minY.isApproximately(10))
        #expect(rect.width.isApproximately(88.888_888_888_9))
        #expect(rect.height.isApproximately(40))
    }

    @Test("A rotated frame maps with its orientation-corrected pixel dimensions")
    func orientationCorrectedDimensions() throws {
        let geometry = try #require(PreviewGeometry(
            frame: frame(width: 1080, height: 1920, rotation: 90),
            viewportSize: CGSize(width: 390, height: 844),
            previewMirrored: false
        ))

        let rect = geometry.rect(for: NormalizedRect(
            x: 0.15,
            y: 0.16,
            width: 0.7,
            height: 0.68
        ))

        #expect(rect.minX.isApproximately(28.8375))
        #expect(rect.minY.isApproximately(135.04))
        #expect(rect.width.isApproximately(332.325))
        #expect(rect.height.isApproximately(573.92))
    }

    @Test("Preview mirroring moves an asymmetric rectangle to the opposite side")
    func previewMirroring() throws {
        let geometry = try #require(PreviewGeometry(
            frame: frame(width: 200, height: 100),
            viewportSize: CGSize(width: 200, height: 100),
            previewMirrored: true
        ))

        let rect = geometry.rect(for: NormalizedRect(
            x: 0.1,
            y: 0.2,
            width: 0.25,
            height: 0.3
        ))

        #expect(rect.minX.isApproximately(130))
        #expect(rect.minY.isApproximately(20))
        #expect(rect.width.isApproximately(50))
        #expect(rect.height.isApproximately(30))
    }

    @Test("Invalid frame and viewport sizes do not produce a mapping")
    func invalidSizes() {
        #expect(PreviewGeometry(
            frame: frame(width: 0, height: 1080),
            viewportSize: CGSize(width: 390, height: 844),
            previewMirrored: false
        ) == nil)
        #expect(PreviewGeometry(
            frame: frame(width: 1920, height: 1080),
            viewportSize: .zero,
            previewMirrored: false
        ) == nil)
    }

    private func frame(
        width: Int,
        height: Int,
        rotation: Double = 0
    ) -> FrameGeometry {
        FrameGeometry(
            pixelWidth: width,
            pixelHeight: height,
            appliedRotation: .degrees(rotation),
            wasMirrored: false
        )
    }
}

private extension CGFloat {
    func isApproximately(_ other: CGFloat, tolerance: CGFloat = 0.000_001) -> Bool {
        abs(self - other) <= tolerance
    }
}
