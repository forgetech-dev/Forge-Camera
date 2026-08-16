import ForgeCore

/// Tolerance for comparing derived floating-point geometry in tests.
///
/// Normalized coordinates are small numbers combined by addition and subtraction, so
/// a round trip lands within a few ULPs rather than on the exact input: `0.2 + 0.4`
/// is `0.6000000000000001`, and flipping a rect twice returns `0.20000000000000007`.
/// Comparisons on *derived* values therefore use a tolerance. Discrete values —
/// axes, actors, counts, enum cases — are still compared exactly, because drift there
/// would be a real defect rather than representation error.
public let geometryTolerance = 1e-9

public extension Double {
    func isApproximately(_ other: Double, tolerance: Double = geometryTolerance) -> Bool {
        Swift.abs(self - other) <= tolerance
    }
}

public extension NormalizedPoint {
    func isApproximately(
        _ other: NormalizedPoint,
        tolerance: Double = geometryTolerance
    ) -> Bool {
        x.isApproximately(other.x, tolerance: tolerance)
            && y.isApproximately(other.y, tolerance: tolerance)
    }
}

public extension NormalizedRect {
    func isApproximately(
        _ other: NormalizedRect,
        tolerance: Double = geometryTolerance
    ) -> Bool {
        x.isApproximately(other.x, tolerance: tolerance)
            && y.isApproximately(other.y, tolerance: tolerance)
            && width.isApproximately(other.width, tolerance: tolerance)
            && height.isApproximately(other.height, tolerance: tolerance)
    }
}

public extension Angle {
    func isApproximately(_ other: Angle, tolerance: Double = geometryTolerance) -> Bool {
        degrees.isApproximately(other.degrees, tolerance: tolerance)
    }
}
