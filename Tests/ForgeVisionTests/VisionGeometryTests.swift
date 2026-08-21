import ForgeCore
import Testing
import Vision
@testable import ForgeVision

/// The Vision → domain coordinate boundary.
///
/// This is where a whole class of "the overlay is subtly wrong" bugs lives, so the
/// fixtures are deliberately off-centre and non-square: a centred square passes a
/// broken vertical flip and would prove nothing.
@Suite("Vision coordinate conversion")
struct VisionGeometryTests {
    @Test("A Vision rect's origin corner moves, not just its axis")
    func rectOriginMoves() {
        // Vision: origin bottom-left at (0.1, 0.2), extending up to y = 0.6.
        let vision = Vision.NormalizedRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)

        let forge = vision.forgeRect

        // The Forge top edge is 1 minus Vision's *top* edge (0.6), not 1 minus its
        // origin (0.2). Confusing the two is wrong by exactly the rect's height.
        #expect(abs(forge.y - 0.4) < 1e-9)
        #expect(abs(forge.maxY - 0.8) < 1e-9)
        #expect(abs(forge.x - 0.1) < 1e-9)
        #expect(abs(forge.width - 0.3) < 1e-9)
        #expect(abs(forge.height - 0.4) < 1e-9)
    }

    @Test("A rect low in the Vision frame is high in the Forge frame")
    func verticalDirectionIsInverted() {
        let lowInVision = Vision.NormalizedRect(x: 0.4, y: 0.05, width: 0.2, height: 0.1)
        let highInVision = Vision.NormalizedRect(x: 0.4, y: 0.85, width: 0.2, height: 0.1)

        // Vision y increases upward, Forge y increases downward.
        #expect(lowInVision.forgeRect.y > highInVision.forgeRect.y)
    }

    @Test("A point at the top of the Vision frame is at the top of the Forge frame")
    func pointConversion() {
        let visionTop = Vision.NormalizedPoint(x: 0.25, y: 0.9)

        let forge = visionTop.forgePoint

        #expect(abs(forge.x - 0.25) < 1e-9)
        // Vision y = 0.9 is near the top, which in Forge space is a small y.
        #expect(abs(forge.y - 0.1) < 1e-9)
    }

    @Test("Converted geometry stays inside the frame")
    func conversionStaysInFrame() {
        let cases = [
            Vision.NormalizedRect(x: 0, y: 0, width: 1, height: 1),
            Vision.NormalizedRect(x: 0, y: 0, width: 0.1, height: 0.1),
            Vision.NormalizedRect(x: 0.9, y: 0.9, width: 0.1, height: 0.1),
            Vision.NormalizedRect(x: 0.33, y: 0.11, width: 0.42, height: 0.27),
        ]

        for vision in cases {
            let forge = vision.forgeRect
            #expect(forge.isWellFormed, "\(forge) escaped the unit square")
        }
    }

    @Test("A full-frame rect converts to a full-frame rect")
    func fullFrameIsPreserved() {
        let forge = Vision.NormalizedRect(x: 0, y: 0, width: 1, height: 1).forgeRect

        #expect(abs(forge.x) < 1e-9)
        #expect(abs(forge.y) < 1e-9)
        #expect(abs(forge.width - 1) < 1e-9)
        #expect(abs(forge.height - 1) < 1e-9)
    }

    @Test("A rect's corners map to the corresponding opposite corners")
    func cornersMapConsistently() {
        // Bottom-left in Vision must become top-left in Forge.
        let bottomLeft = Vision.NormalizedRect(x: 0, y: 0, width: 0.2, height: 0.3)
        let forge = bottomLeft.forgeRect

        #expect(abs(forge.minX) < 1e-9)
        #expect(abs(forge.maxY - 1) < 1e-9)
    }

    @Test("Forge and Vision rect conversion round-trips")
    func forgeRectRoundTrips() {
        let forge = ForgeCore.NormalizedRect(x: 0.13, y: 0.27, width: 0.41, height: 0.19)

        let roundTripped = forge.visionRect.forgeRect

        #expect(abs(roundTripped.x - forge.x) < 1e-9)
        #expect(abs(roundTripped.y - forge.y) < 1e-9)
        #expect(abs(roundTripped.width - forge.width) < 1e-9)
        #expect(abs(roundTripped.height - forge.height) < 1e-9)
    }
}
