import ForgeCore
import Foundation
import Vision

// Vision reports normalized geometry with the origin at the bottom-left and y
// increasing upward. The domain uses the top-left with y increasing downward.
//
// Every conversion happens here, once, at the boundary. The rect case is the one that
// bites: the origin corner moves as well as the axis direction, so a rect flipped as
// though it were a point is wrong by exactly its own height.
//
// Names are fully qualified throughout. Vision has its own `NormalizedPoint` and
// `NormalizedRect` — different types, different convention, identical spelling — and
// an unqualified reference in this module is ambiguous rather than merely confusing.

extension ForgeCore.NormalizedPoint {
    /// A Vision point converted into Forge normalized frame space.
    init(vision point: Vision.NormalizedPoint) {
        self.init(x: Double(point.x), y: 1 - Double(point.y))
    }
}

extension ForgeCore.NormalizedRect {
    /// A Vision rect converted into Forge normalized frame space.
    init(vision rect: Vision.NormalizedRect) {
        let originX = Double(rect.origin.x)
        let originY = Double(rect.origin.y)
        let width = Double(rect.width)
        let height = Double(rect.height)
        self.init(
            x: originX,
            // The top edge in Forge space is 1 minus Vision's *top* edge, which is its
            // origin plus its height — not 1 minus its origin.
            y: 1 - (originY + height),
            width: width,
            height: height
        )
    }
}

extension Vision.NormalizedRect {
    /// This Vision rect in Forge normalized frame space.
    var forgeRect: ForgeCore.NormalizedRect {
        ForgeCore.NormalizedRect(vision: self)
    }
}

extension Vision.NormalizedPoint {
    /// This Vision point in Forge normalized frame space.
    var forgePoint: ForgeCore.NormalizedPoint {
        ForgeCore.NormalizedPoint(vision: self)
    }
}
