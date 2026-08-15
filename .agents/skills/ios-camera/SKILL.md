---
name: ios-camera
description: Build and modify the native iOS camera pipeline for AI Photographer using AVFoundation — AVCaptureSession setup, AVCaptureVideoDataOutput frame delivery, AVCapturePhotoOutput stills, CVPixelBuffer handling, preview rendering, rotation, focus/exposure/white-balance control, permissions, interruption and lifecycle handling, thermal and performance management. Use when touching capture, preview, frame delivery, camera switching, photo capture, or camera latency on iPhone. Do not use for external/mirrorless camera control (use camera-integration) or for Vision/ARKit analysis of frames (use vision-spatial).
license: Apache-2.0
metadata:
  project: ai-photographer
  last_verified: "2026-08-15"
  platform: "iOS 18+, Swift 6"
---

# iOS Camera Pipeline

Native AVFoundation capture for AI Photographer's Phone Camera Mode. This skill covers getting
frames out of the camera correctly, quickly, and on the right threads. It does **not** cover what
to do with those frames — see `vision-spatial` for analysis and `ios-ui-design` for presentation.

## Non-negotiable rules

1. **Native AVFoundation only.** No third-party camera wrappers. The platform API is the contract.
2. **Preview must never stall.** If a frame costs too much to process, drop it. A frozen preview is
   a broken product; a skipped analysis frame is invisible.
3. **No heavy work on the main thread.** Vision, pixel math, and encoding run off-main. The main
   actor only receives small value types for rendering.
4. **No `UIImage` or JPEG in the realtime path.** Carry `CVPixelBuffer` / `CMSampleBuffer` through
   capture → analysis. Encoding exists only at the AI-request boundary and at final capture.
5. **Never send every frame to a remote service.** Realtime perception is local. See
   `photography-director` for the event-driven planning cadence.
6. **Separate capture, analysis, and presentation.** Three components, one direction of data flow.
   Capture does not know about Vision. Vision does not know about SwiftUI.
7. **Measure, don't guess.** Latency and frame-rate claims require a measurement. See
   [references/performance.md](references/performance.md).
8. **Own the lifecycle.** Interruptions, backgrounding, route changes, and runtime errors are normal
   operating conditions, not edge cases.

## Architecture this skill assumes

```
AVCaptureSession
  ├── AVCaptureDeviceInput            (camera)
  ├── AVCaptureVideoDataOutput        → serial queue → SceneAnalyzer → SceneState
  └── AVCapturePhotoOutput            → capture → full-quality still
AVCaptureVideoPreviewLayer            (preview, driven directly by the session)
```

`FrameSource` is the protocol boundary. `AVFoundationFrameSource` is one implementation;
`RecordedFrameSource` is another. Nothing above the protocol may reference AVFoundation types.

## Session setup

Configure inside a single `beginConfiguration()` / `commitConfiguration()` pair, on a dedicated
session queue — never the main queue. `AVCaptureSession.startRunning()` blocks; calling it on main
freezes the UI.

```swift
private let sessionQueue = DispatchQueue(label: "camera.session")
private let videoQueue = DispatchQueue(label: "camera.video")   // frame delivery only
```

Key choices:

- **`sessionPreset`**: prefer an explicit `.hd1920x1080` or an `activeFormat` chosen deliberately
  over `.photo` when you need predictable video frame geometry. `.photo` gives a still-optimized
  format whose video dimensions may surprise you.
- **`alwaysDiscardsLateVideoFrames = true`** on `AVCaptureVideoDataOutput`. This is the
  back-pressure mechanism. Without it, frames queue and guidance goes stale.
- **`videoSettings`**: request an explicit pixel format. `kCVPixelFormatType_420YpCbCr8BiPlanarFullRange`
  is the normal choice for Vision + Metal. Do not accept whatever comes back by default.
- Set `automaticallyConfiguresApplicationAudioSession = false` — the app captures no audio.

## Frame delivery

`captureOutput(_:didOutput:from:)` is called on your `videoQueue`. Treat it as a hot path:

- **Do not retain the `CMSampleBuffer` or its `CVPixelBuffer` beyond the callback.** AVFoundation
  uses a finite buffer pool; holding buffers stalls capture. Extract what you need, or copy.
- **Latest-wins, buffer of one.** If the analyzer is busy, drop the frame. Never build a queue.
- Timestamp from `CMSampleBufferGetPresentationTimeStamp`, not `Date()`. The pipeline needs a single
  monotonic clock so recorded sessions replay deterministically.
- `CVPixelBufferLockBaseAddress` only when reading CPU-side, and always balance the unlock.

A correct drop pattern (an actor with a single in-flight slot, or an atomic `isAnalyzing` flag
checked on the video queue) is required. See [references/avfoundation.md](references/avfoundation.md).

## Rotation — use RotationCoordinator

`AVCaptureConnection.videoOrientation` is **deprecated as of iOS 17**. Use
`AVCaptureDevice.RotationCoordinator` and apply its angle to
`AVCaptureConnection.videoRotationAngle`:

- `videoRotationAngleForHorizonLevelPreview` → the preview connection.
- `videoRotationAngleForHorizonLevelCapture` → photo/video-data connections.
- Observe both via KVO; they change independently of UI orientation.
- Angles are degrees in `[0, 360)`; portrait is `90`.

Hold a strong reference to the coordinator — it stops reporting if deallocated. Rotation is the
single most common source of "the overlay doesn't line up with the image" bugs; get it right once,
at the boundary, and convert into Forge's normalized frame space there.

## Focus, exposure, white balance

Always wrap in `lockForConfiguration()` / `unlockForConfiguration()`, and always check the
corresponding `isFocusModeSupported(_:)` / `isExposureModeSupported(_:)` /
`isWhiteBalanceModeSupported(_:)` first. Capability checks are not optional — front cameras,
ultra-wide, and external devices differ.

- Point-of-interest coordinates are in **device coordinates**, not view or Vision coordinates.
  Convert with `AVCaptureVideoPreviewLayer.captureDevicePointConverted(fromLayerPoint:)`.
- Prefer continuous modes for the live loop; switch to locked modes only for a deliberate capture.
- Observe `adjustingFocus` / `adjustingExposure` before declaring the frame ready to analyze.

## Photo capture

`AVCapturePhotoOutput` with an explicit `AVCapturePhotoSettings`. Notes that matter here:

- Set `maxPhotoQualityPrioritization` on the output **before** the session runs, and the per-shot
  `photoQualityPrioritization` at or below it.
- The delegate returns on an arbitrary queue. Hop deliberately.
- The full-quality still, not the preview frame, is what post-shot review analyzes (see `goal.md`
  §8). Keep the capture path separate from the video-data path.
- Bracketed capture for HDR uses `AVCapturePhotoBracketSettings`; check
  `maxBracketedCapturePhotoCount` before offering it.

## Permissions and lifecycle

- `AVCaptureDevice.requestAccess(for: .video)`; handle `.denied` and `.restricted` with a path to
  Settings. `NSCameraUsageDescription` is required in `Info.plist`.
- Observe `AVCaptureSessionWasInterrupted` / `...InterruptionEnded` and inspect `reason`
  (phone call, another app took the camera, Slide Over/Split View, thermal shutdown). Show state;
  do not silently die.
- Observe `AVCaptureSessionRuntimeError` and attempt a bounded restart.
- Stop the session on background, restart on foreground. Never leave the camera running unseen.

## Thermal and power

Sustained capture plus per-frame Vision will heat an iPhone. Observe
`ProcessInfo.processInfo.thermalStateDidChangeNotification` and degrade deliberately:

| `thermalState` | Response |
|---|---|
| `.nominal` / `.fair` | full analysis rate |
| `.serious` | halve the analysis rate, keep preview at full rate |
| `.critical` | analysis to a minimum, tell the user, keep preview alive |

Degradation is a product behavior (`goal.md` §17), not a silent optimization — surface it.

## Testability

Camera code is testable if the AVFoundation surface stays thin:

- `FrameSource` is a protocol; production and recorded implementations are interchangeable.
- Conversion functions (rotation → normalized space, device point ↔ normalized point, buffer
  geometry) are **pure and unit-tested**. These carry the bugs.
- Anything requiring a real camera goes in hardware-gated tests and never in ordinary CI. See
  `opensource-quality`.

## References

- [references/avfoundation.md](references/avfoundation.md) — session, output, buffer, and rotation
  specifics with official sources.
- [references/performance.md](references/performance.md) — latency budgets, measurement technique,
  thermal behavior.

## Related skills

`vision-spatial` (analysis of the frames), `ios-ui-design` (preview and HUD presentation),
`camera-integration` (external cameras behind the same `FrameSource` protocol),
`opensource-quality` (module boundaries, testability).
