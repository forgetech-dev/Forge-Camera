/// The zoom factor currently applied by the phone camera and the range exposed to the UI.
public struct CameraZoomState: Sendable, Equatable {
    /// The factor currently applied to the active capture device.
    public let factor: Double
    /// The smallest factor supported by the active capture device.
    public let minimumFactor: Double
    /// The largest factor the App deliberately exposes for interactive zoom.
    public let maximumFactor: Double

    init(
        factor: Double,
        deviceMinimumFactor: Double,
        deviceMaximumFactor: Double
    ) {
        let minimum = if deviceMinimumFactor.isFinite, deviceMinimumFactor > 0 {
            deviceMinimumFactor
        } else {
            1.0
        }
        let hardwareMaximum = if deviceMaximumFactor.isFinite {
            deviceMaximumFactor
        } else {
            minimum
        }
        let maximum = max(
            minimum,
            min(hardwareMaximum, CameraZoomPolicy.maximumInteractiveFactor)
        )

        minimumFactor = minimum
        maximumFactor = maximum
        self.factor = min(max(factor, minimum), maximum)
    }

    /// Restricts a requested zoom factor to the range this camera exposes.
    public func clampedFactor(_ requestedFactor: Double) -> Double {
        guard requestedFactor.isFinite else { return minimumFactor }
        return min(max(requestedFactor, minimumFactor), maximumFactor)
    }
}

private enum CameraZoomPolicy {
    /// Higher digital factors remain technically available on some devices but are
    /// not useful as a hand-held composition control in this first product slice.
    static let maximumInteractiveFactor = 8.0
}
