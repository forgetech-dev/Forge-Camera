# Vision, ARKit, CoreMotion, Depth — Project Reference

**Purpose.** The on-device perception APIs this project uses, what each is actually good for, and
where each stops being trustworthy.

**Last verified:** 2026-08-15 against iOS 18.0 SDK.

---

## Vision (iOS 18 Swift API)

iOS 18 introduced a Swift-native Vision API: requests drop the `VN` prefix, observations are returned
directly from `perform()`, and the whole surface is async/await and `Sendable`-friendly. Use it. The
legacy `VNRequest` completion-handler API still exists for back-deployment but fights Swift 6 strict
concurrency.

| Request | Use here | Notes |
|---|---|---|
| `DetectHumanRectanglesRequest` | Fast subject presence and bounds | Cheapest human detector. |
| `DetectHumanBodyPoseRequest` | Pose guidance, body orientation | Set `detectsHands` for holistic pose. Most expensive request in the pipeline. |
| `DetectHumanBodyPose3DRequest` | 3D pose where available | Verify device support and cost before depending on it. |
| `DetectFaceRectanglesRequest` | Face presence, head position | Cheap. |
| Face landmarks / face capture quality | Head orientation, eye state | Head yaw/pitch/roll is the useful output for `headYaw` in the plan. |
| `GenerateForegroundInstanceMaskRequest` | Subject/background separation | Useful for background-conflict detection; costly per frame. |
| `DetectHorizonRequest` | Horizon angle | Cross-check against CoreMotion gravity, which is cheaper and usually better. |
| Tracking requests | Identity stability across frames | Prefer over re-detection for stable `SubjectID`s. |
| `DetectAnimalBodyPoseRequest` | Pets as subjects | Later; not core. |

### Behavior that matters

- **Batch through one `ImageRequestHandler`.** One handler per frame, all requests together — Vision
  shares work across requests in a single pass.
- **Resolution drives cost.** Downscale before analysis. Body pose at 4K costs far more than at 720p
  and rarely finds more people.
- **Confidence is on every observation.** Propagate it. A low-confidence wrist joint is not a fact,
  and pose-derived guidance must weight by joint confidence.
- **Orientation must be declared** when constructing the handler (see
  [coordinate-systems.md](coordinate-systems.md)). Wrong orientation gives plausible-looking but
  wrong detections — the worst failure mode.
- **Requests have revisions.** Pin deliberately if behavior must stay stable across OS updates, and
  record the revision in recorded sessions so replays stay comparable.
- Vision runs on the Neural Engine where available, so wall-clock cost is not proportional to CPU
  time. Measure on device (`ios-camera` → performance.md).

## ARKit

The source of genuinely metric camera pose.

- `ARWorldTrackingConfiguration` gives `ARCamera.transform` — a metric 6-DoF camera pose in a
  world frame. This is what makes "move left 40 cm" possible for the *photographer*.
- **`ARCamera.trackingState` is a gate, not a diagnostic.** Only `.normal` justifies metric output.
  `.limited(.initializing / .excessiveMotion / .insufficientFeatures / .relocalizing)` means relative
  cues only. Check it every frame, per cue.
- `ARCamera.intrinsics` gives the 3×3 intrinsic matrix — the precise route to angular math.
- `ARBodyTrackingConfiguration` gives a metric skeleton but has real constraints (typically one
  person, specific orientation, device requirements). Verify before designing around it.
- **ARKit and AVFoundation compete for the camera.** They cannot both drive capture. If ARKit runs,
  frames come from `ARFrame.capturedImage`. Decide per capture mode, at the composition root, and
  make the tradeoff explicit — do not attempt to run both.
- ARKit costs significant power and thermal budget. It is part of the degradation ladder.

## Depth and LiDAR

- `ARFrame.sceneDepth` (LiDAR devices) gives metric depth plus a **confidence map**. Use the
  confidence map; edges, dark surfaces, reflective and transparent materials are unreliable.
- `AVCaptureDepthDataOutput` provides depth outside ARKit on supporting devices.
- Non-Pro devices have no LiDAR. Depth-derived guidance must degrade, not disappear.
- Depth at the subject's silhouette edge is the least reliable place, which is unfortunately where
  subject-distance sampling is tempting. Sample from the interior of the subject region.

## CoreMotion

Cheap, reliable, and underrated for this project.

- `CMMotionManager.deviceMotion.gravity` gives the gravity vector → **exact roll and pitch**.
  Horizon leveling and camera-tilt cues are metric-accurate with no depth and no ARKit.
- Available when ARKit is not, and vastly cheaper.
- `attitude` provides orientation but drifts in yaw; do not use it for absolute heading.
- Update at a rate matched to the analysis loop, not the maximum available.

Rule of thumb: **angles are cheap, distances are expensive.** Take the free angular accuracy.

## Core ML

Only if Apple's built-ins genuinely fall short — a custom model is a maintenance burden, an app-size
cost, and a new failure surface.

If used: quantize, compile at build time, run on the Neural Engine, and keep it behind the
`SceneAnalyzer` protocol so it stays swappable and testable. Never make a custom model a hard
requirement for the app to function.

## Optical flow

`VNGenerateOpticalFlowRequest` produces dense flow. Useful for motion-blur risk and for camera-motion
estimation without ARKit, but it is expensive. Do not add it to the per-frame path without a measured
justification.

## Pitfalls

- Running Vision on the main thread, or on the same queue as capture delivery.
- Retaining `CVPixelBuffer` past the analysis call (see `ios-camera`).
- Ignoring `trackingState` and emitting metric cues during `.limited`.
- Ignoring per-joint confidence and producing pose guidance from a hallucinated skeleton.
- Assuming LiDAR exists.
- Trying to run ARKit and an `AVCaptureSession` simultaneously.
- Re-detecting every frame instead of tracking, so `SubjectID`s churn and guidance jumps between
  people.
- Treating `DetectHorizonRequest` as more authoritative than gravity. It is not, and it is dearer.

## Official sources

- Vision: https://developer.apple.com/documentation/vision
- `DetectHumanBodyPoseRequest`: https://developer.apple.com/documentation/vision/detecthumanbodyposerequest
- WWDC24 — "Discover Swift enhancements in the Vision framework" (session 10163):
  https://developer.apple.com/videos/play/wwdc2024/10163/
- ARKit: https://developer.apple.com/documentation/arkit
- `ARCamera`: https://developer.apple.com/documentation/arkit/arcamera
- `ARFrame.sceneDepth`: https://developer.apple.com/documentation/arkit/arframe/scenedepth
- Core Motion: https://developer.apple.com/documentation/coremotion
- Core ML: https://developer.apple.com/documentation/coreml

## Open questions

- Measured per-frame cost of `DetectHumanBodyPoseRequest` at candidate analysis resolutions on the
  target device. **Requires hardware verification.** Sets the analysis rate and the downscale factor.
- Device support and cost of `DetectHumanBodyPose3DRequest`, and whether it beats 2D pose plus depth.
- Whether `ARBodyTrackingConfiguration`'s constraints are compatible with a photography workflow
  (subject orientation, distance, single-subject limits).
- Whether the ARKit-vs-AVFoundation tradeoff should be user-visible ("precision mode") or automatic.
