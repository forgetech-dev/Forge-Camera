import Foundation
@testable import ForgeCapture

/// A controllable permission boundary.
///
/// Records how many prompts were opened and can hold one open indefinitely, which is
/// what makes the interesting lifecycle races reachable without a camera: stopping
/// mid-prompt, backgrounding mid-prompt, and two starts racing for one prompt.
final class StubCameraAuthorization: CameraAuthorization, @unchecked Sendable {
    private let lock = NSLock()
    private var _status: CameraAuthorizationStatus
    private var _grant: Bool
    private var _requestCount = 0
    /// Every waiter, not one. Concurrent starts each open their own await, and a
    /// single-slot gate silently dropped all but the last — which deadlocked the
    /// suite rather than failing it.
    private var gates: [CheckedContinuation<Void, Never>] = []
    private var isGated: Bool
    private var isReleased = false

    init(status: CameraAuthorizationStatus, grants: Bool = true, holdsPrompt: Bool = false) {
        _status = status
        _grant = grants
        isGated = holdsPrompt
    }

    var status: CameraAuthorizationStatus {
        lock.withLock { _status }
    }

    /// How many times the system prompt was opened. Two concurrent starts must
    /// produce one, not two.
    var requestCount: Int {
        lock.withLock { _requestCount }
    }

    /// Blocks until `releasePrompt()` when the stub was created gated.
    func requestAccess() async -> Bool {
        let shouldWait: Bool = lock.withLock {
            _requestCount += 1
            return isGated && !isReleased
        }

        if shouldWait {
            await withCheckedContinuation { continuation in
                let resumeNow: Bool = lock.withLock {
                    if isReleased {
                        return true
                    }
                    gates.append(continuation)
                    return false
                }
                if resumeNow {
                    continuation.resume()
                }
            }
        }

        return lock.withLock {
            _status = _grant ? .authorized : .denied
            return _grant
        }
    }

    /// Lets every held prompt answer, including any that arrives later.
    func releasePrompt() {
        let waiting: [CheckedContinuation<Void, Never>] = lock.withLock {
            isReleased = true
            defer { gates.removeAll() }
            return gates
        }
        waiting.forEach { $0.resume() }
    }

    /// Spins until the prompt is actually open, so a test never races the await.
    func waitForPromptToOpen() async {
        while requestCount == 0 {
            await Task.yield()
        }
    }
}
