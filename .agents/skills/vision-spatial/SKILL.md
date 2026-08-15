---
name: vision-spatial
description: Realtime on-device perception and spatial reasoning for AI Photographer — Apple Vision (human/face detection, 2D and 3D body pose, segmentation, tracking), Core ML, ARKit camera pose and depth, LiDAR, CoreMotion gravity, camera intrinsics, optical flow, coordinate transforms, and rig calibration between an iPhone and an external camera. Enforces the distinction between image-space guidance and metric world-space guidance so the app never fabricates precision. Use when working on scene analysis, subject tracking, horizon estimation, depth, distance estimation, coordinate conversion, or any guidance that claims a real-world measurement.
license: Apache-2.0
metadata:
  project: ai-photographer
  last_verified: "2026-08-15"
  platform: "iOS 18+, Swift 6"
---

# Vision and Spatial Reasoning

Local perception runs at frame rate and produces `SceneState`. It is the fast half of the system;
the AI Director is the slow half (`photography-director`). This skill governs everything that turns
pixels into structured spatial facts — and, critically, governs what those facts are allowed to
claim.

## The central distinction

Two fundamentally different kinds of guidance, never to be conflated:

| | Image-space | Metric world-space |
|---|---|---|
| Source | Detections in the frame | ARKit pose, LiDAR depth, calibrated geometry |
| Knows | Where things are *in the picture* | Where things are *in the room* |
| Can say | "Move left", "step closer", "lower the camera" | "Move left 40 cm" |
| Always available | Yes | No |

**Image-space guidance is always available and always honest. Metric guidance requires earned
evidence.** The default is image-space. Metric is an upgrade that must be justified per-cue, per-frame.

> **Never fabricate precision.** "Move left 43 cm" without a valid metric estimate is worse than
> useless — it destroys trust in every other thing the app says.

This is enforced structurally, not by discipline: `GuidanceMagnitude` is
`.metric(meters:confidence:)` or `.relative(.slight/.moderate/.large)`, with no bare `Double`.
A cue built without metric provenance cannot carry units. Any code that would need to "just convert"
a relative cue into meters is a bug being written.

## Measurement provenance

Every spatial quantity carries where it came from:

```swift
struct Measured<T: Sendable>: Sendable {
    let value: T
    let confidence: Double          // 0…1
    let provenance: Provenance      // .lidar, .arkitDepth, .arkitPose, .intrinsics,
}                                   // .estimated, .userProvided
```

`.estimated` — for example, subject distance inferred from apparent face size — is **not** metric.
It informs relative magnitude and never prints a unit. Promoting an estimate to a measurement is the
single most likely way this project betrays its users.

## What is genuinely metric, and when

| Source | Metric? | Conditions |
|---|---|---|
| ARKit camera pose translation | Yes | `ARCamera.trackingState == .normal`. Degrades on fast motion, low texture, poor light. |
| LiDAR scene depth | Yes | Pro devices only. Check confidence map; edges and dark/reflective surfaces are unreliable. |
| ARKit body anchor (`ARBodyTrackingConfiguration`) | Yes | Single-person, front-facing constraints. Verify on device. |
| Camera intrinsics + known object size | Yes | Only if the real size is genuinely known. |
| Subject on-screen size ratio | **Relative only** | Gives dolly *ratio* without any metric scale — see below. |
| Face-size heuristic distance | No | `.estimated`. Head sizes vary far too much. |
| Gravity vector (CoreMotion) | Yes, for **angles** | Roll and pitch are metric without any depth. Use it. |

### The size-ratio result worth knowing

Subject on-screen height scales as `1/distance` at fixed focal length, so:

```
d_target / d_current = s_current / s_target
```

The subject's real height **cancels out**. The *ratio* of the required move is computable from image
data alone — "get to 80% of your current distance" — with no metric knowledge whatsoever. Metric
scale is needed only for the final unit conversion.

This is why `Measured` matters: the same computation produces "step forward" or "step forward 40 cm"
depending on one input, with no separate code path. Build the ratio first; attach units last, if
earned.

### Angles are cheap, distances are expensive

Gravity from CoreMotion gives roll and pitch **exactly**, with no depth, no ARKit, no calibration.
Horizon leveling and camera-tilt guidance can therefore be metric-accurate even when everything else
is relative. Do not let the difficulty of distances hold back the angular guidance that is free.

With focal length and sensor geometry (or `videoFieldOfView`), image position converts to angle
exactly under a pinhole model:

```
yaw(x) = atan((2x − 1) · tan(θ_h / 2))
```

If FOV or focal length is unknown, this degrades to relative — see `goal.md` §17 and the
manual-focal-length path in `camera-integration`.

## Coordinate systems — the top source of bugs

Six conventions are in play and they disagree about origin, axis direction, and orientation. Vision
uses a bottom-left origin; UIKit uses top-left; AVFoundation device space is defined in the sensor's
native landscape orientation; ARKit is right-handed 3D in meters.

**The project defines one internal convention and converts at every boundary:**

> **Forge normalized frame space** — origin **top-left**, x → right, y → down, both in `[0, 1]`,
> measured on the **orientation-corrected, as-displayed** image.

Every adapter converts at its own edge. `ForgeCore` never sees a foreign convention. Every conversion
is a pure function with a round-trip unit test. Full table and conversion rules in
[references/coordinate-systems.md](references/coordinate-systems.md) — **read it before writing any
conversion**.

Other binding conventions: distances in **meters** (SI internally, units only at the presentation
layer); angles in **degrees**, positive counter-clockwise by the right-hand rule; timestamps from the
frame's presentation time on one monotonic clock.

## Vision framework usage

iOS 18 provides the modern Swift Vision API — `ImageRequestHandler`, requests named without the `VN`
prefix, observations returned directly from `perform()`, async/await throughout. Use it; the legacy
`VNRequest` completion-handler API fights Swift 6 concurrency.

- **Batch requests through one `ImageRequestHandler`** per frame. One handler, many requests, one
  pass over the image.
- Downscale before analysis. Body pose at 4K costs enormously more than at 720p and rarely detects
  more.
- `DetectHumanBodyPoseRequest` with `detectsHands` for holistic pose;
  `DetectHumanBodyPose3DRequest` where available; `DetectFaceRectanglesRequest` /
  face-landmarks for orientation; segmentation for subject/background separation.
- Every observation has a **confidence**. Propagate it into `SceneState`; never treat a low-confidence
  joint as a fact.
- Tracking: prefer Vision's tracking over re-detecting every frame for identity stability, and assign
  stable `SubjectID`s so guidance does not jump between people.

Details and pitfalls in [references/vision-arkit.md](references/vision-arkit.md).

## Temporal stability

Raw per-frame detections jitter. Guidance computed from raw detections is unusable.

- Smooth subject bounds and joints with a **One Euro filter** — low lag while moving, strong
  smoothing while still. A plain EMA forces a choice between lag and jitter; One Euro does not.
- Smoothing lives in the perception/guidance layer, never in the view. A view-layer animation hiding
  jitter conceals a real bug and adds latency.
- Deadband and hysteresis belong to the guidance engine, but they depend on stable input from here.

## Rig calibration (external camera mode)

When an iPhone is rigidly mounted to a mirrorless camera, the phone's ARKit pose can describe the
external camera's motion — but only after the fixed transform between them is known.

**Do not build a calibration system yet.** Build the principles in now so it is possible later:

- `MotionSource` is a separate protocol from `FrameSource`, so the pose provider and the image
  provider are independently swappable.
- `MotionCoupling` (`.rigid` / `.decoupled` / `.unknown`) is declared explicitly at composition time.
  `GuidanceEngine` refuses to emit `.metric` photographer cues unless coupling is `.rigid`.
- Hand-held phone + tripod camera is `.decoupled` — all photographer cues become relative. This is
  the correct answer, not a limitation to work around.

Principles for the eventual implementation are in
[references/rig-calibration.md](references/rig-calibration.md).

## References

- [references/coordinate-systems.md](references/coordinate-systems.md) — all six conventions and the
  conversion rules. Read before writing conversions.
- [references/vision-arkit.md](references/vision-arkit.md) — Vision, ARKit, CoreMotion, depth APIs
  with behavior, limits, and sources.
- [references/rig-calibration.md](references/rig-calibration.md) — extrinsic calibration principles.

## Related skills

`ios-camera` (frame delivery and intrinsics), `photography-director` (what the plan asks for),
`ios-ui-design` (how honesty is rendered), `opensource-quality` (pure functions, determinism).
