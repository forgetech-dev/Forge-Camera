import ForgeFrame

public extension AVFoundationFrameSource {
    /// Delivers one independently owned live frame for an explicit planning request.
    ///
    /// This is a one-shot side channel rather than a second consumer of `frames`, so
    /// AI preparation cannot steal frames from or queue work behind realtime analysis.
    func nextPlanningFrame() async -> PixelBufferFrame? {
        await withCheckedContinuation { continuation in
            videoQueue.async { [self] in
                frameDelivery.requestPlanningFrame(continuation)
            }
        }
    }
}
