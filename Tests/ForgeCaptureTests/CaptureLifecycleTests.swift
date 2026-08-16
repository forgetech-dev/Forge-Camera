import Foundation
import Testing
@testable import ForgeCapture

/// Lifecycle behaviour that resolves before any camera hardware is touched.
///
/// Every case here completes during permission handling, so it runs on a machine with
/// no camera, no device, and no simulator. Anything that needs a configured session is
/// a hardware test and does not belong in this suite.
@Suite("Capture lifecycle")
struct CaptureLifecycleTests {
    private func source(
        _ authorization: StubCameraAuthorization,
        backgrounded: @escaping @Sendable () async -> Bool = { false }
    ) -> AVFoundationFrameSource {
        AVFoundationFrameSource(
            authorization: authorization,
            applicationIsBackgrounded: backgrounded
        )
    }

    /// Collects statuses without keeping the stream open past the test.
    private func statuses(
        of source: AVFoundationFrameSource,
        while body: @Sendable () async -> Void
    ) async -> [CaptureStatus] {
        let collector = Task {
            var seen: [CaptureStatus] = []
            for await status in source.statuses {
                seen.append(status)
            }
            return seen
        }
        await body()
        // Cancelling ends the stream iteration, so the task returns what it collected
        // rather than throwing.
        collector.cancel()
        return await collector.value
    }

    // MARK: Permission outcomes

    @Test("A denied camera fails the start with an actionable error")
    func deniedPermissionFailsStart() async {
        let source = source(StubCameraAuthorization(status: .denied))

        await #expect(throws: CaptureError.permissionDenied) {
            try await source.start()
        }
    }

    @Test("A restricted camera is distinguished from a denied one")
    func restrictedPermissionIsItsOwnError() async {
        let source = source(StubCameraAuthorization(status: .restricted))

        // The user can act on a denial; a restriction is imposed on them. The
        // recovery suggestions differ, so the errors must too.
        await #expect(throws: CaptureError.permissionRestricted) {
            try await source.start()
        }
    }

    @Test("An already-authorized camera never opens a prompt")
    func authorizedCameraSkipsThePrompt() async {
        let authorization = StubCameraAuthorization(status: .authorized)
        let source = source(authorization)

        // Reaching hardware configuration is expected to fail on a machine with no
        // camera; what matters is that no prompt was shown.
        _ = try? await source.start()

        #expect(authorization.requestCount == 0)
    }

    @Test("Refusing the prompt fails the start")
    func refusedPromptFailsStart() async {
        let authorization = StubCameraAuthorization(status: .notDetermined, grants: false)
        let source = source(authorization)

        await #expect(throws: CaptureError.permissionDenied) {
            try await source.start()
        }
        #expect(authorization.requestCount == 1)
    }

    // MARK: Concurrency

    @Test("Concurrent starts all resolve and agree on the outcome")
    func concurrentStartsResolveConsistently() async {
        let authorization = StubCameraAuthorization(
            status: .notDetermined,
            grants: false,
            holdsPrompt: true
        )
        let source = source(authorization)

        let starts = (0 ..< 3).map { _ in
            Task { () -> Bool in
                do {
                    try await source.start()
                    return true
                } catch {
                    return false
                }
            }
        }

        await authorization.waitForPromptToOpen()
        authorization.releasePrompt()
        var outcomes: [Bool] = []
        for start in starts {
            await outcomes.append(start.value)
        }

        // What matters is that none of the three hangs and none disagrees. Each
        // caller queries permission independently — AVFoundation coalesces the
        // visible prompt, so the redundancy costs nothing the user can see and
        // deduplicating it would add machinery for no observable gain.
        #expect(outcomes.count == 3)
        #expect(Set(outcomes) == [false])
    }

    // MARK: Interruption during the prompt

    @Test("Stopping during the prompt cancels the pending start")
    func stopDuringPromptCancelsStart() async {
        let authorization = StubCameraAuthorization(status: .notDetermined, holdsPrompt: true)
        let source = source(authorization)

        let starting = Task { try await source.start() }
        await authorization.waitForPromptToOpen()
        await source.stop()
        authorization.releasePrompt()

        await #expect(throws: CancellationError.self) {
            try await starting.value
        }
    }

    @Test("Backgrounding during the prompt cancels the pending start")
    func backgroundDuringPromptCancelsStart() async {
        let authorization = StubCameraAuthorization(status: .notDetermined, holdsPrompt: true)
        let isBackgrounded = Backgrounded()
        let source = source(authorization, backgrounded: { await isBackgrounded.value })

        let starting = Task { try await source.start() }
        await authorization.waitForPromptToOpen()
        // The user answered the prompt after leaving the app. Acting on that answer
        // would open the camera while backgrounded, which the OS forbids.
        await isBackgrounded.set(true)
        authorization.releasePrompt()

        await #expect(throws: CancellationError.self) {
            try await starting.value
        }
    }

    @Test("Cancelling the calling task cancels the start")
    func taskCancellationCancelsStart() async {
        let authorization = StubCameraAuthorization(status: .notDetermined, holdsPrompt: true)
        let source = source(authorization)

        let starting = Task { try await source.start() }
        await authorization.waitForPromptToOpen()
        starting.cancel()
        authorization.releasePrompt()

        await #expect(throws: CancellationError.self) {
            try await starting.value
        }
    }

    // MARK: Status reporting

    @Test("A pending prompt is published so the UI can explain the wait")
    func promptIsPublishedAsStatus() async {
        let authorization = StubCameraAuthorization(
            status: .notDetermined,
            grants: false,
            holdsPrompt: true
        )
        let source = source(authorization)

        let seen = await statuses(of: source) {
            let starting = Task { try? await source.start() }
            await authorization.waitForPromptToOpen()
            authorization.releasePrompt()
            _ = await starting.value
        }

        #expect(seen.contains(.awaitingPermission))
    }

    @Test("A denied start ends in a failed status carrying the error")
    func denialIsPublishedAsFailure() async {
        let authorization = StubCameraAuthorization(status: .denied)
        let source = source(authorization)

        let seen = await statuses(of: source) {
            _ = try? await source.start()
        }

        #expect(seen.contains(.failed(.permissionDenied)))
    }

    @Test("Stopping an idle source is safe and reports idle")
    func stoppingIdleSourceIsSafe() async {
        let source = source(StubCameraAuthorization(status: .authorized))

        await source.stop()
        await source.stop()

        #expect(await source.currentRunID == 0)
    }
}

/// Mutable backgrounded state a test can flip while a start is in flight.
private actor Backgrounded {
    private(set) var value = false

    func set(_ newValue: Bool) {
        value = newValue
    }
}
