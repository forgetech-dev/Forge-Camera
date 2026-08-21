import AVFoundation

#if os(iOS)
    public extension AVFoundationFrameSource {
        /// Requests a new zoom factor without blocking the main actor.
        ///
        /// The request is clamped to the active camera's supported interactive range and
        /// applied on the same serial queue that owns the capture session. The resulting
        /// device value is then published through ``zoomStates``.
        func setZoomFactor(_ requestedFactor: Double) {
            sessionQueue.async { [weak self] in
                guard let self, let device = activeVideoDevice else { return }

                let priorState = zoomState(for: device)
                let factor = priorState.clampedFactor(requestedFactor)
                do {
                    try device.lockForConfiguration()
                    device.videoZoomFactor = CGFloat(factor)
                    device.unlockForConfiguration()
                    zoomContinuation.yield(zoomState(for: device))
                } catch {
                    Self.logger.error("Unable to apply camera zoom")
                }
            }
        }
    }

    extension AVFoundationFrameSource {
        /// Reads AVFoundation state only from `sessionQueue`.
        func zoomState(for device: AVCaptureDevice) -> CameraZoomState {
            CameraZoomState(
                factor: Double(device.videoZoomFactor),
                deviceMinimumFactor: Double(device.minAvailableVideoZoomFactor),
                deviceMaximumFactor: Double(device.maxAvailableVideoZoomFactor)
            )
        }
    }
#endif
