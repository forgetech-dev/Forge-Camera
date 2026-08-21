import Foundation

// MARK: - Forge normalized frame space

//
// Origin top-left, x increases right, y increases DOWN, both in [0, 1],
// measured on the orientation-corrected, as-displayed image.
//
// This is the only 2D convention used inside ForgeCore. Vision (bottom-left
// origin) and AVFoundation device space (sensor-native landscape) are foreign
// conventions that adapters convert at their own boundary.

/// A point in Forge normalized frame space.
public struct NormalizedPoint: Sendable, Equatable, Codable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let center = NormalizedPoint(x: 0.5, y: 0.5)

    /// True when both components lie inside the unit square.
    public var isInsideFrame: Bool {
        (0 ... 1).contains(x) && (0 ... 1).contains(y)
    }

    /// Clamps both components into `[0, 1]`.
    public func clamped() -> NormalizedPoint {
        NormalizedPoint(x: x.clampedToUnitInterval, y: y.clampedToUnitInterval)
    }

    /// Converts from a bottom-left-origin space (such as Vision's) into Forge space.
    ///
    /// Only the y axis differs for a point, so this is its own inverse.
    public func flippedVertically() -> NormalizedPoint {
        NormalizedPoint(x: x, y: 1 - y)
    }
}

/// A rectangle in Forge normalized frame space, with its origin at the top-left corner.
public struct NormalizedRect: Sendable, Equatable, Codable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Double {
        x
    }

    public var minY: Double {
        y
    }

    public var maxX: Double {
        x + width
    }

    public var maxY: Double {
        y + height
    }

    public var midX: Double {
        x + width / 2
    }

    public var midY: Double {
        y + height / 2
    }

    public var center: NormalizedPoint {
        NormalizedPoint(x: midX, y: midY)
    }

    public var area: Double {
        width * height
    }

    /// A rect is well formed when it has non-negative extent and stays inside the frame.
    public var isWellFormed: Bool {
        width >= 0 && height >= 0
            && minX >= 0 && minY >= 0
            && maxX <= 1 + .ulpOfOne && maxY <= 1 + .ulpOfOne
    }

    /// Converts from a bottom-left-origin space (such as Vision's) into Forge space.
    ///
    /// Unlike a point, the origin corner moves as well as the axis direction: the
    /// rect's own height has to be subtracted. Flipping a rect as though it were a
    /// point is the classic bug here, and it is wrong by exactly `height`.
    public func flippedVertically() -> NormalizedRect {
        NormalizedRect(x: x, y: 1 - maxY, width: width, height: height)
    }

    /// Clamps the rect into the unit square, preserving a non-negative extent.
    public func clamped() -> NormalizedRect {
        let left = minX.clampedToUnitInterval
        let top = minY.clampedToUnitInterval
        let right = maxX.clampedToUnitInterval
        let bottom = maxY.clampedToUnitInterval
        return NormalizedRect(
            x: left,
            y: top,
            width: max(0, right - left),
            height: max(0, bottom - top)
        )
    }

    public func contains(_ point: NormalizedPoint) -> Bool {
        point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
    }

    /// Fractional overlap with another rect, relative to this rect's own area.
    ///
    /// Used to decide whether a subject intrudes into a region the plan asks to avoid.
    public func overlapFraction(with other: NormalizedRect) -> Double {
        guard area > 0 else { return 0 }
        let overlapWidth = max(0, min(maxX, other.maxX) - max(minX, other.minX))
        let overlapHeight = max(0, min(maxY, other.maxY) - max(minY, other.minY))
        return (overlapWidth * overlapHeight) / area
    }

    /// Moves and uniformly scales this rect with an image-space tracking region.
    ///
    /// The receiver is the AI director's original target frame. `referenceRegion`
    /// is the selected subject region from that same planning image, and
    /// `trackedRegion` is where local perception sees that subject now. The result
    /// preserves the target frame's aspect ratio while following the subject's
    /// apparent translation and scale change.
    ///
    /// The result is intentionally not clamped to the unit square. A target frame
    /// extending beyond the preview honestly tells the UI that the photographer
    /// still needs to move the camera; clamping would distort the composition.
    public func projected(
        from referenceRegion: NormalizedRect,
        to trackedRegion: NormalizedRect
    ) -> NormalizedRect? {
        let values = [
            x, y, width, height,
            referenceRegion.x, referenceRegion.y,
            referenceRegion.width, referenceRegion.height,
            trackedRegion.x, trackedRegion.y,
            trackedRegion.width, trackedRegion.height,
        ]
        guard values.allSatisfy(\.isUsableNumber),
              width > 0,
              height > 0,
              referenceRegion.width > 0,
              referenceRegion.height > 0,
              trackedRegion.width > 0,
              trackedRegion.height > 0
        else {
            return nil
        }

        // Width and height can jitter independently as the tracked object's outline
        // changes. Their geometric mean retains the real common zoom component while
        // keeping the photographic frame's aspect ratio stable.
        let widthScale = trackedRegion.width / referenceRegion.width
        let heightScale = trackedRegion.height / referenceRegion.height
        let scale = sqrt(widthScale * heightScale)
        guard scale.isUsableNumber, scale > 0 else { return nil }

        let offsetX = (midX - referenceRegion.midX) * scale
        let offsetY = (midY - referenceRegion.midY) * scale
        let projectedWidth = width * scale
        let projectedHeight = height * scale
        let projectedMidX = trackedRegion.midX + offsetX
        let projectedMidY = trackedRegion.midY + offsetY

        return NormalizedRect(
            x: projectedMidX - projectedWidth / 2,
            y: projectedMidY - projectedHeight / 2,
            width: projectedWidth,
            height: projectedHeight
        )
    }
}

// MARK: - Frame geometry

/// The resolved geometry of a delivered frame.
///
/// Orientation is resolved exactly once, at the capture boundary, and recorded here.
/// Downstream code reads this and never re-derives orientation — every place that
/// independently decides "are we in portrait?" is a future bug.
public struct FrameGeometry: Sendable, Equatable, Codable {
    /// Pixel width of the orientation-corrected image.
    public let pixelWidth: Int
    /// Pixel height of the orientation-corrected image.
    public let pixelHeight: Int
    /// Rotation already applied to reach the upright, as-displayed image, in degrees.
    public let appliedRotation: Angle
    /// Whether the source was mirrored. `SceneState` is always un-mirrored; this
    /// records what had to be undone so guidance never inverts lateral cues.
    public let wasMirrored: Bool

    public init(pixelWidth: Int, pixelHeight: Int, appliedRotation: Angle, wasMirrored: Bool) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.appliedRotation = appliedRotation
        self.wasMirrored = wasMirrored
    }

    /// Width divided by height of the orientation-corrected image.
    public var aspectRatio: Double {
        guard pixelHeight > 0 else { return 0 }
        return Double(pixelWidth) / Double(pixelHeight)
    }
}

// MARK: - Helpers

extension Double {
    var clampedToUnitInterval: Double {
        Swift.min(1, Swift.max(0, self))
    }

    /// True for values that are safe to compute with: finite, not NaN.
    ///
    /// A NaN reaching the guidance engine poisons every downstream computation
    /// silently, so untrusted input is checked with this before use.
    public var isUsableNumber: Bool {
        isFinite && !isNaN
    }
}
