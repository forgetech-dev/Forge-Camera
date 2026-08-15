# AVFoundation Capture — Project Reference

**Purpose.** The specific AVFoundation behaviors that AI Photographer's capture layer depends on.
Not a tutorial and not a mirror of Apple's docs — only what has bitten real camera pipelines.

**Last verified:** 2026-08-15 against iOS 18.0 SDK / Xcode 16.0.

---

## Relevant APIs

| Type | Role |
|---|---|
| `AVCaptureSession` | Graph owner. Configure between `beginConfiguration()`/`commitConfiguration()`. |
| `AVCaptureDevice` | Physical camera. Source of format, focal length, focus/exposure control. |
| `AVCaptureDeviceInput` | Adapts a device into the session. |
| `AVCaptureVideoDataOutput` | Realtime frames via `AVCaptureVideoDataOutputSampleBufferDelegate`. |
| `AVCapturePhotoOutput` | Full-quality stills, bracketing, RAW. |
| `AVCaptureConnection` | Per-output connection; carries `videoRotationAngle`, mirroring, stabilization. |
| `AVCaptureVideoPreviewLayer` | Preview. Also does view ↔ device coordinate conversion. |
| `AVCaptureDevice.RotationCoordinator` | iOS 17+ source of truth for rotation angles. |
| `AVCaptureDevice.DiscoverySession` | Enumerate devices by type/position. |
| `CMSampleBuffer` / `CVPixelBuffer` | The frame itself, plus timing metadata. |

## Important behavior

**Configuration is transactional.** Changes between `beginConfiguration()` and
`commitConfiguration()` apply atomically. Configuring outside that pair can drop frames or
reconfigure the graph mid-flight.

**`startRunning()` blocks.** It can take hundreds of milliseconds. Always on a background queue.

**Two distinct queues.** A serial session queue for configuration and start/stop, and a separate
serial queue for `AVCaptureVideoDataOutput` sample delivery. Sharing one queue makes configuration
changes stall frame delivery.

**`alwaysDiscardsLateVideoFrames`.** Defaults to `true`. Keep it `true`. This is how AVFoundation
applies back-pressure: if the delegate is still busy, the new frame is dropped rather than queued.
Setting it to `false` and doing slow work is the classic way to build unbounded latency.

**Buffer pool exhaustion.** `CMSampleBuffer`s come from a fixed-size pool. Retaining them past the
delegate callback starves the pool and capture stalls — often presenting as "the camera freezes
after ~10 seconds". Extract or copy; do not store.

**Format vs preset.** `sessionPreset` is a coarse convenience. For predictable geometry and frame
rate, select an `AVCaptureDevice.Format` explicitly and set `activeFormat` plus
`activeVideoMinFrameDuration` / `activeVideoMaxFrameDuration` inside a device configuration lock.
Setting `activeFormat` overrides `sessionPreset`.

**Focal length and FOV.** `AVCaptureDevice.Format` does not directly publish focal length in mm.
`videoFieldOfView` gives the horizontal FOV in degrees for the active format — this is the practical
input for the angular math in `vision-spatial`. Camera intrinsics (a 3×3 matrix) can be attached to
sample buffers when `isCameraIntrinsicMatrixDeliveryEnabled` is set on the connection, which requires
the format to support it. Intrinsics are the more precise route; FOV is the always-available one.

**Rotation.** `videoOrientation` is deprecated (iOS 17). `AVCaptureDevice.RotationCoordinator`
publishes `videoRotationAngleForHorizonLevelPreview` and
`videoRotationAngleForHorizonLevelCapture` as KVO-observable degree values in `[0, 360)`. They are
distinct: preview follows the interface, capture follows gravity-level intent. Apply to the relevant
`AVCaptureConnection.videoRotationAngle` after checking
`isVideoRotationAngleSupported(_:)`. The coordinator must be retained.

**Coordinate conversion.** `AVCaptureVideoPreviewLayer` provides
`captureDevicePointConverted(fromLayerPoint:)` and `layerPointConverted(fromCaptureDevicePoint:)`.
Device space is `(0,0)` top-left to `(1,1)` bottom-right **in the sensor's landscape-left native
orientation**, which is not the same as Vision's normalized space or Forge's normalized space. Every
hop must be explicit. See `vision-spatial` for the full conversion table.

**Multi-camera.** `AVCaptureMultiCamSession` allows simultaneous devices on supported hardware
(`isMultiCamSupported`). It costs significant power and thermal headroom. Not needed for the core
loop; do not adopt speculatively.

**External cameras.** `AVCaptureDevice.DeviceType.external` exists on iOS 17+. Whether an iPhone
(as opposed to iPad) exposes a USB-C UVC camera through it is **unverified** and must be tested on
device before any design depends on it. See `camera-integration`.

## Implementation pitfalls

- Calling `startRunning()` on the main thread → visible hitch on entry to the capture screen.
- Forgetting `lockForConfiguration()` before touching focus/exposure/WB → runtime exception.
- Assuming a capability exists → always `isXSupported` first. Devices differ widely.
- Using `Date()` for frame timestamps → non-deterministic replay, broken tracking.
- Retaining pixel buffers for later analysis → capture stalls.
- Applying rotation in the view layer instead of at the pipeline boundary → overlay misalignment
  that reappears every time a new surface is added.
- Setting `photoQualityPrioritization` above the output's `maxPhotoQualityPrioritization` →
  exception. Set the max before the session starts.
- Leaving the session running in the background → battery drain and an OS interruption.

## Official sources

- AVFoundation Capture: https://developer.apple.com/documentation/avfoundation/capture_setup
- `AVCaptureSession`: https://developer.apple.com/documentation/avfoundation/avcapturesession
- `AVCaptureVideoDataOutput`: https://developer.apple.com/documentation/avfoundation/avcapturevideodataoutput
- `AVCapturePhotoOutput`: https://developer.apple.com/documentation/avfoundation/avcapturephotooutput
- `AVCaptureDevice.RotationCoordinator`: https://developer.apple.com/documentation/avfoundation/avcapturedevice/rotationcoordinator
- `videoRotationAngle`: https://developer.apple.com/documentation/avfoundation/avcaptureconnection/videorotationangle
- Deprecated `videoOrientation`: https://developer.apple.com/documentation/avfoundation/avcaptureconnection/videoorientation
- WWDC23 "Support HDR images in your app" and WWDC21 "What's new in camera capture" for capture
  pipeline evolution: https://developer.apple.com/videos/

## Open questions

- Does an iPhone (not iPad) running iOS 18 expose a USB-C UVC camera via
  `AVCaptureDevice.DeviceType.external`? **Requires hardware verification.** Determines whether
  External Camera Mode can avoid a Mac bridge entirely.
- Which `AVCaptureDevice.Format`s on the target device support
  `isCameraIntrinsicMatrixDeliveryEnabled` at 1080p and the frame rates we want? Affects whether
  metric angular guidance uses intrinsics or falls back to `videoFieldOfView`.
- Measured cost of `AVCaptureMultiCamSession` if wide + ultra-wide are ever both needed.
