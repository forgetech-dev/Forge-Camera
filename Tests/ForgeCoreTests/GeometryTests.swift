import ForgeTestSupport
import Testing
@testable import ForgeCore

@Suite("Normalized geometry")
struct GeometryTests {
    /// A rect's origin corner moves as well as the axis direction when flipping, so the
    /// fixture is deliberately off-centre and non-square. A centred square passes a
    /// broken flip, which is why symmetric test data is banned here.
    let asymmetric = NormalizedRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)

    @Test("Flipping a rect vertically moves the origin corner, not just the axis")
    func rectFlipMovesOrigin() {
        let flipped = asymmetric.flippedVertically()

        // Top edge becomes 1 - bottom edge.
        #expect(flipped.minY.isApproximately(1 - asymmetric.maxY))
        #expect(flipped.maxY.isApproximately(1 - asymmetric.minY))
        // Horizontal geometry and extent are untouched — these are copied, not
        // derived, so they must match exactly.
        #expect(flipped.minX == asymmetric.minX)
        #expect(flipped.width == asymmetric.width)
        #expect(flipped.height == asymmetric.height)
    }

    @Test("Flipping a rect twice is the identity")
    func rectFlipRoundTrips() {
        let roundTripped = asymmetric.flippedVertically().flippedVertically()
        #expect(roundTripped.isApproximately(asymmetric))
    }

    @Test("Flipping a rect is not the same as flipping its origin point")
    func rectFlipDiffersFromPointFlip() {
        // The classic bug is wrong by exactly the rect's height.
        let wrong = 1 - asymmetric.minY
        let right = asymmetric.flippedVertically().minY
        #expect(wrong != right)
        #expect(abs(wrong - right).isApproximately(asymmetric.height))
    }

    @Test("Flipping a point twice is the identity")
    func pointFlipRoundTrips() {
        let point = NormalizedPoint(x: 0.25, y: 0.75)
        #expect(point.flippedVertically().flippedVertically() == point)
    }

    @Test("Rect centre and edges agree")
    func rectCentre() {
        #expect(asymmetric.center.x == 0.25)
        #expect(abs(asymmetric.center.y - 0.4) < 1e-12)
    }

    @Test("Clamping keeps a rect inside the frame with non-negative extent")
    func clampingKeepsRectWellFormed() {
        let overflowing = NormalizedRect(x: -0.5, y: 0.8, width: 2, height: 0.9)
        let clamped = overflowing.clamped()

        #expect(clamped.isWellFormed)
        #expect(clamped.minX >= 0)
        #expect(clamped.maxY <= 1)
        #expect(clamped.width >= 0)
        #expect(clamped.height >= 0)
    }

    @Test("A rect fully outside the frame clamps to zero area rather than a negative one")
    func fullyOutsideRectClampsToZeroArea() {
        let outside = NormalizedRect(x: 1.5, y: 1.5, width: 0.2, height: 0.2)
        let clamped = outside.clamped()

        #expect(clamped.width == 0)
        #expect(clamped.height == 0)
        #expect(clamped.isWellFormed)
    }

    @Test("Overlap fraction is measured against the receiver's own area")
    func overlapFraction() {
        let subject = NormalizedRect(x: 0, y: 0, width: 0.4, height: 0.4)
        let half = NormalizedRect(x: 0.2, y: 0, width: 0.4, height: 0.4)

        #expect(abs(subject.overlapFraction(with: half) - 0.5) < 1e-12)
        #expect(subject.overlapFraction(with: subject) == 1)
        #expect(subject.overlapFraction(
            with: NormalizedRect(x: 0.9, y: 0.9, width: 0.05, height: 0.05)
        ) == 0)
    }

    @Test("A target frame follows selection translation")
    func targetFrameFollowsTranslation() throws {
        let target = NormalizedRect(x: 0.1, y: 0.15, width: 0.6, height: 0.7)
        let initial = NormalizedRect(x: 0.2, y: 0.3, width: 0.2, height: 0.2)
        let moved = NormalizedRect(x: 0.35, y: 0.2, width: 0.2, height: 0.2)

        let projected = try #require(target.projected(from: initial, to: moved))

        #expect(projected.x.isApproximately(target.x + 0.15))
        #expect(projected.y.isApproximately(target.y - 0.1))
        #expect(projected.width.isApproximately(target.width))
        #expect(projected.height.isApproximately(target.height))
    }

    @Test("A target frame grows uniformly with selection zoom")
    func targetFrameFollowsZoom() throws {
        let target = NormalizedRect(x: 0.2, y: 0.2, width: 0.4, height: 0.5)
        let initial = NormalizedRect(x: 0.4, y: 0.4, width: 0.1, height: 0.2)
        let zoomed = NormalizedRect(x: 0.35, y: 0.3, width: 0.2, height: 0.4)

        let projected = try #require(target.projected(from: initial, to: zoomed))

        // The target centre's offset from the subject also scales. Here the target
        // starts 0.05 left/up of the selected subject, so a 2x zoom doubles that
        // offset while the selected subject centre remains fixed.
        #expect(projected.center.x.isApproximately(0.35))
        #expect(projected.center.y.isApproximately(0.4))
        #expect(projected.width.isApproximately(target.width * 2))
        #expect(projected.height.isApproximately(target.height * 2))
        #expect((projected.width / projected.height).isApproximately(target.width / target.height))
    }

    @Test("Tracking outline deformation does not distort the target aspect ratio")
    func targetFrameUsesUniformScale() throws {
        let target = NormalizedRect(x: 0.2, y: 0.25, width: 0.4, height: 0.5)
        let initial = NormalizedRect(x: 0.3, y: 0.3, width: 0.2, height: 0.2)
        let deformed = NormalizedRect(x: 0.2, y: 0.35, width: 0.4, height: 0.1)

        let projected = try #require(target.projected(from: initial, to: deformed))

        #expect(projected.width.isApproximately(target.width))
        #expect(projected.height.isApproximately(target.height))
    }

    @Test("Invalid tracking geometry is rejected")
    func invalidTrackingGeometryIsRejected() {
        let target = NormalizedRect(x: 0.2, y: 0.2, width: 0.5, height: 0.5)
        let empty = NormalizedRect(x: 0.4, y: 0.4, width: 0, height: 0.2)
        let tracked = NormalizedRect(x: 0.3, y: 0.3, width: 0.2, height: 0.2)

        #expect(target.projected(from: empty, to: tracked) == nil)
    }

    @Test("A projected target may remain outside the preview")
    func projectedTargetIsNotClamped() throws {
        let target = NormalizedRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        let initial = NormalizedRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
        let moved = NormalizedRect(x: 0.8, y: 0.4, width: 0.2, height: 0.2)

        let projected = try #require(target.projected(from: initial, to: moved))

        #expect(projected.maxX > 1)
    }

    @Test("Frame aspect ratio follows the orientation-corrected pixel size")
    func aspectRatio() {
        let landscape = FrameGeometry(
            pixelWidth: 1920, pixelHeight: 1080, appliedRotation: .zero, wasMirrored: false
        )
        let portrait = FrameGeometry(
            pixelWidth: 1080, pixelHeight: 1920, appliedRotation: .degrees(90), wasMirrored: false
        )

        #expect(abs(landscape.aspectRatio - 16.0 / 9.0) < 1e-12)
        #expect(abs(portrait.aspectRatio - 9.0 / 16.0) < 1e-12)
    }

    @Test("Non-finite values are rejected as unusable")
    func unusableNumbers() {
        #expect(!Double.nan.isUsableNumber)
        #expect(!Double.infinity.isUsableNumber)
        #expect(!(-Double.infinity).isUsableNumber)
        #expect(0.0.isUsableNumber)
        #expect((-1.5).isUsableNumber)
    }
}

@Suite("Angles and field of view")
struct AngleTests {
    @Test("Wrapping produces the shortest equivalent rotation")
    func wrapping() {
        #expect(Angle.degrees(350).wrapped().degrees == -10)
        #expect(Angle.degrees(-350).wrapped().degrees == 10)
        #expect(Angle.degrees(180).wrapped().degrees == 180)
        #expect(Angle.degrees(-180).wrapped().degrees == 180)
        #expect(Angle.degrees(0).wrapped().degrees == 0)
        #expect(Angle.degrees(720).wrapped().degrees == 0)
    }

    @Test("Wrapping normalises negative zero so output is stable")
    func wrappingNormalisesNegativeZero() {
        let wrapped = Angle.degrees(-360).wrapped()
        #expect(wrapped.degrees == 0)
        #expect(wrapped.degrees.sign == .plus)
    }

    @Test("Degrees and radians convert round-trip")
    func radiansRoundTrip() {
        let original = Angle.degrees(37.5)
        #expect(abs(Angle.radians(original.radians).degrees - 37.5) < 1e-12)
    }

    @Test("Frame centre is on the optical axis")
    func centreIsZeroAngle() {
        let fov = FieldOfView(horizontal: .degrees(60), vertical: .degrees(40))
        #expect(abs(fov.horizontalAngle(atNormalizedX: 0.5).degrees) < 1e-12)
        #expect(abs(fov.verticalAngle(atNormalizedY: 0.5).degrees) < 1e-12)
    }

    @Test("Frame edges sit at half the field of view")
    func edgesAreHalfTheFieldOfView() {
        let fov = FieldOfView(horizontal: .degrees(60), vertical: .degrees(40))
        #expect(abs(fov.horizontalAngle(atNormalizedX: 1).degrees - 30) < 1e-9)
        #expect(abs(fov.horizontalAngle(atNormalizedX: 0).degrees + 30) < 1e-9)
    }

    @Test("A position below frame centre is a downward tilt")
    func verticalSignFollowsForgeConvention() {
        let fov = FieldOfView(horizontal: .degrees(60), vertical: .degrees(40))
        // Forge y increases downward, so y = 0.9 is low in the frame.
        #expect(fov.verticalAngle(atNormalizedY: 0.9).degrees < 0)
        #expect(fov.verticalAngle(atNormalizedY: 0.1).degrees > 0)
    }

    @Test("Field of view derived from aspect ratio is narrower vertically in landscape")
    func derivedVerticalFieldOfView() throws {
        let fov = try #require(FieldOfView(horizontal: .degrees(60), aspectRatio: 16.0 / 9.0))
        #expect(fov.vertical.degrees < fov.horizontal.degrees)
        #expect(fov.vertical.degrees > 0)
    }

    @Test("Nonsensical field of view inputs are rejected rather than producing NaN")
    func invalidFieldOfViewRejected() {
        #expect(FieldOfView(horizontal: .degrees(60), aspectRatio: 0) == nil)
        #expect(FieldOfView(horizontal: .degrees(0), aspectRatio: 1.5) == nil)
        #expect(FieldOfView(horizontal: .degrees(180), aspectRatio: 1.5) == nil)
    }
}

@Suite("Measurement provenance")
struct MeasuredTests {
    @Test("Only genuinely metric sources may carry units")
    func provenanceDecidesMetric() {
        #expect(MeasurementProvenance.lidar.isMetric)
        #expect(MeasurementProvenance.arkitDepth.isMetric)
        #expect(MeasurementProvenance.arkitPose.isMetric)
        #expect(MeasurementProvenance.intrinsics.isMetric)
        #expect(MeasurementProvenance.userProvided.isMetric)
        // Inferred from image cues alone. Never metric, however confident.
        #expect(!MeasurementProvenance.estimated.isMetric)
    }

    @Test("A confident estimate is still not a measurement")
    func confidentEstimateIsNotMetric() {
        let estimate = Measured(value: 2.0, confidence: 0.99, provenance: .estimated)
        #expect(!estimate.isTrustworthyMetric(minimumConfidence: 0.6))
    }

    @Test("A metric source below the confidence floor is not trusted")
    func lowConfidenceMetricIsNotTrusted() {
        let vague = Measured(value: 2.0, confidence: 0.2, provenance: .lidar)
        #expect(!vague.isTrustworthyMetric(minimumConfidence: 0.6))
        #expect(vague.isTrustworthyMetric(minimumConfidence: 0.1))
    }

    @Test("Confidence is clamped into the unit interval")
    func confidenceClamped() {
        #expect(Measured(value: 1.0, confidence: 5, provenance: .lidar).confidence == 1)
        #expect(Measured(value: 1.0, confidence: -3, provenance: .lidar).confidence == 0)
    }
}
