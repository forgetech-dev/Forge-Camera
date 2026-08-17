import AVFoundation
import Foundation
#if os(iOS)
    import UIKit
#endif

extension AVFoundationFrameSource {
    func installSessionObservers() {
        let center = NotificationCenter.default
        notificationObservers.append(center.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification,
            object: session,
            queue: nil
        ) { [weak self] notification in
            guard let source = self else { return }
            let code = (notification.userInfo?[AVCaptureSessionErrorKey] as? NSError)?.code
            source.sessionQueue.async {
                source.handleRuntimeError(code: code)
            }
        })
        #if os(iOS)
            notificationObservers.append(center.addObserver(
                forName: AVCaptureSession.wasInterruptedNotification,
                object: session,
                queue: nil
            ) { [weak self] notification in
                guard let source = self else { return }
                let rawReason = (
                    notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber
                )?.intValue
                source.sessionQueue.async {
                    source.handleInterruption(rawReason: rawReason)
                }
            })
            notificationObservers.append(center.addObserver(
                forName: AVCaptureSession.interruptionEndedNotification,
                object: session,
                queue: nil
            ) { [weak self] _ in
                guard let source = self else { return }
                source.sessionQueue.async {
                    source.handleInterruptionEnded()
                }
            })
        #endif
    }

    func installApplicationObservers() {
        #if os(iOS)
            let center = NotificationCenter.default
            notificationObservers.append(center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                guard let source = self else { return }
                source.sessionQueue.async {
                    source.handleEnteredBackground()
                }
            })
            notificationObservers.append(center.addObserver(
                forName: UIApplication.willEnterForegroundNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                guard let source = self else { return }
                source.sessionQueue.async {
                    source.handleEnteredForeground()
                }
            })
        #endif
    }

    /// Handles one bounded recovery attempt after media services reset. sessionQueue only.
    ///
    /// The recovery path is compiled only where it can run. Reducing it to a `false`
    /// constant elsewhere left a condition the compiler proved unreachable, which
    /// Swift 6.1 reports as dead code — correctly, since a platform-specific recovery
    /// does not belong in a platform-neutral branch.
    private func handleRuntimeError(code: Int?) {
        guard requestedRunning, !isApplicationInBackground else { return }

        #if os(iOS)
            // One attempt only: a session that cannot be restarted twice will not be
            // restarted by trying again.
            if code == AVError.Code.mediaServicesWereReset.rawValue, !attemptedRuntimeRestart {
                attemptedRuntimeRestart = true
                activateDelivery()
                session.startRunning()
                if session.isRunning {
                    statusContinuation.yield(.running)
                    return
                }
            }
        #endif

        Self.logger.error("Capture session runtime failure")
        failCurrentAttempt(.runtimeFailure)
    }

    func handleEnteredBackground() {
        isApplicationInBackground = true
        guard requestedRunning else { return }
        if session.isRunning || hasCompletedStart {
            stoppedForBackground = true
            stopSessionAndDeactivateDelivery()
        } else {
            // A pending permission/configuration attempt has no valid graph to
            // restart. Its caller receives cancellation and may retry foregrounded.
            lifecycleGeneration &+= 1
            requestedRunning = false
            startWaiters.removeAll()
            hasCompletedStart = false
            stoppedForBackground = false
            deactivateDelivery()
        }
        statusContinuation.yield(.interrupted(.background))
    }

    #if os(iOS)
        private func handleInterruption(rawReason: Int?) {
            guard requestedRunning else { return }
            let reason = rawReason.flatMap(AVCaptureSession.InterruptionReason.init(rawValue:))
            statusContinuation.yield(.interrupted(captureInterruption(for: reason)))
        }

        private func handleInterruptionEnded() {
            guard requestedRunning,
                  !isApplicationInBackground,
                  !stoppedForBackground
            else { return }
            if !session.isRunning {
                activateDelivery()
                session.startRunning()
            }
            if session.isRunning {
                statusContinuation.yield(.running)
            } else {
                failCurrentAttempt(.sessionFailedToStart)
            }
        }

        private func handleEnteredForeground() {
            isApplicationInBackground = false
            guard requestedRunning else {
                stoppedForBackground = false
                statusContinuation.yield(.idle)
                return
            }
            guard stoppedForBackground, isConfigured else {
                stoppedForBackground = false
                return
            }
            stoppedForBackground = false
            activateDelivery()
            session.startRunning()
            if session.isRunning {
                statusContinuation.yield(.running)
            } else {
                failCurrentAttempt(.sessionFailedToStart)
            }
        }

        private func captureInterruption(
            for reason: AVCaptureSession.InterruptionReason?
        ) -> CaptureInterruption {
            switch reason {
            case .audioDeviceInUseByAnotherClient?, .videoDeviceInUseByAnotherClient?:
                .anotherClient
            case .videoDeviceNotAvailableWithMultipleForegroundApps?:
                .multipleForegroundApps
            case .videoDeviceNotAvailableDueToSystemPressure?:
                .systemPressure
            case .videoDeviceNotAvailableInBackground?:
                .background
            case nil:
                .unknown
            case .some:
                .unknown
            }
        }
    #endif

    func activateDelivery() {
        videoQueue.sync {
            frameDelivery.activate()
        }
    }

    func deactivateDelivery() {
        videoQueue.sync {
            frameDelivery.deactivate()
        }
    }

    func stopSessionAndDeactivateDelivery() {
        if session.isRunning {
            session.stopRunning()
        }
        deactivateDelivery()
    }

    /// Ends the active generation and publishes its terminal status. sessionQueue only.
    func failCurrentAttempt(_ error: CaptureError) {
        lifecycleGeneration &+= 1
        requestedRunning = false
        startWaiters.removeAll()
        hasCompletedStart = false
        stoppedForBackground = false
        attemptedRuntimeRestart = false
        stopSessionAndDeactivateDelivery()
        statusContinuation.yield(.failed(error))
    }
}
