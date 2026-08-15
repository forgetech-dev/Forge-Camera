# Coordinate Systems — Normative Reference

**Purpose.** Six coordinate conventions are in play in this app and they disagree. This file is the
single authority on which is which and how to convert. Read it before writing any conversion.

**Last verified:** 2026-08-15.

---

## The project convention

> **Forge normalized frame space**
> Origin **top-left**. x increases **right**, y increases **down**. Both in `[0, 1]`.
> Measured on the **orientation-corrected, as-displayed** image.

`ForgeCore` and every domain type use this and only this. Adapters convert at their own boundary.

## The six conventions

| System | Origin | y axis | Range | Orientation |
|---|---|---|---|---|
| **Forge normalized** | top-left | down | `[0,1]` | as displayed, upright |
| **Vision** | **bottom-left** | **up** | `[0,1]` | of the image passed in, plus the orientation you declared |
| **AVFoundation device space** | top-left | down | `[0,1]` | sensor's **native landscape** orientation |
| **UIKit** | top-left | down | points | view coordinates, upright |
| **SwiftUI** | top-left | down | points | view coordinates, upright |
| **ARKit world** | arbitrary | **up** | meters, 3D | right-handed, y is gravity-up |

Two traps live in this table:

1. **Vision's y is flipped** relative to everything else in 2D. `y_forge = 1 − y_vision` for points;
   for rects the origin also moves: `y_forge = 1 − (y_vision + height_vision)`. Getting rects wrong
   by exactly the height of the box is the classic symptom.
2. **AVFoundation device space is not display space.** It is defined in the sensor's native landscape
   orientation regardless of how the phone is held. Converting it as if it were display space
   produces overlays that are right in landscape and wrong in portrait.

## Conversions

### Vision → Forge

```swift
// point
ForgePoint(x: visionPoint.x, y: 1 - visionPoint.y)

// rect: origin moves from bottom-left to top-left
ForgeRect(x: r.minX, y: 1 - r.maxY, width: r.width, height: r.height)
```

Vision's output is relative to the image **and the orientation you declared** when constructing the
`ImageRequestHandler`. Declare it correctly (from the rotation angle, see below) and Vision returns
coordinates in the upright frame — then only the y-flip remains.

### AVFoundation device space ↔ view

Never hand-roll this. Use the preview layer:

```swift
previewLayer.captureDevicePointConverted(fromLayerPoint: p)
previewLayer.layerPointConverted(fromCaptureDevicePoint: p)
```

It accounts for `videoGravity` cropping, mirroring, and rotation — all of which hand-rolled math
gets wrong. This is the correct path for tap-to-focus and for `setFocusPoint`.

### Forge → view (SwiftUI)

```swift
CGPoint(x: forge.x * size.width, y: forge.y * size.height)
```

Valid **only** when the preview fills the view with the same aspect ratio. With
`videoGravity = .resizeAspectFill` the preview is cropped and this is wrong at the edges. Either
compute the visible-rect mapping explicitly or use the preview layer's conversion.

### ARKit → 2D

`ARCamera.projectPoint(_:orientation:viewportSize:)` projects a world point to the viewport, and
`unprojectPoint` / raycasting goes the other way. Pass the same orientation and viewport size the
preview actually uses, or results will be subtly wrong.

## Rotation is part of the conversion

`AVCaptureDevice.RotationCoordinator` supplies `videoRotationAngle` (see `ios-camera`). That angle
determines:

- the `CGImagePropertyOrientation` handed to Vision, and
- whether width and height swap in the geometry.

Resolve rotation **once**, at the capture boundary, and produce a `FrameGeometry` that records the
applied orientation. Downstream code reads `FrameGeometry` and never re-derives orientation. Every
place that independently decides "are we in portrait?" is a future bug.

## Mirroring

The front camera is mirrored for preview. Whether detections arrive mirrored depends on the
connection's `isVideoMirrored`. Decide explicitly:

- Preview may be mirrored (users expect it).
- **`SceneState` is never mirrored.** Guidance says "move left" about the real world; a mirrored
  coordinate space silently inverts every lateral cue.

Record the mirroring decision in `FrameGeometry` and unmirror at the boundary.

## External cameras

An external camera's frames have their own geometry, orientation, and aspect ratio — unrelated to the
iPhone's. The adapter converts into Forge normalized space at its own boundary, exactly like
`AVFoundationFrameSource`. Nothing downstream knows the difference.

Note that the iPhone's ARKit pose describes the *phone*, not the external camera. See
[rig-calibration.md](rig-calibration.md).

## Angle and unit conventions

- **Angles**: degrees, `Double`. Positive = counter-clockwise by the right-hand rule.
  `bodyYaw = 0` means the subject faces the camera.
- **Distances**: meters internally, always. cm/ft/in exist only in the presentation formatter.
- **Time**: monotonic seconds from the frame's presentation timestamp. Never `Date()`.

## Testing conversions

Non-negotiable, because these bugs are invisible until an overlay is subtly wrong:

- **Round-trip property tests**: `forge → other → forge` is identity within epsilon, for random
  points and rects.
- **Corner tests**: each of the four corners maps to the expected corner, for every orientation.
  Symmetric test data (a centered square) passes broken code — use asymmetric fixtures.
- **Orientation matrix**: all four device orientations × front/back camera.
- **Rect y-flip**: explicitly test a non-centered rect, since a centered one survives a wrong flip.

## Pitfalls

- Flipping y for rects as if they were points (off by the rect's height).
- Treating AVFoundation device space as display space.
- Recomputing orientation in more than one place.
- Letting mirrored coordinates into `SceneState`.
- Assuming the preview view and the frame share an aspect ratio under `.resizeAspectFill`.
- Mixing degrees and radians. Domain types use degrees; trig needs radians; convert at the call site
  and name variables accordingly.

## Official sources

- Vision coordinate conventions: https://developer.apple.com/documentation/vision
- `VNImagePointForNormalizedPoint` / normalized-point helpers: https://developer.apple.com/documentation/vision/vnimagepointfornormalizedpoint
- `AVCaptureVideoPreviewLayer` conversions: https://developer.apple.com/documentation/avfoundation/avcapturevideopreviewlayer
- `ARCamera.projectPoint`: https://developer.apple.com/documentation/arkit/arcamera
- `CGImagePropertyOrientation`: https://developer.apple.com/documentation/imageio/cgimagepropertyorientation

## Open questions

- Exact geometry of `videoGravity = .resizeAspectFill` cropping for the formats this app uses —
  needed for correct edge-region overlay placement.
- Whether external-camera live view should be letterboxed or cropped to match the phone preview's
  behavior, and what that means for guidance drawn near frame edges.
