---
name: camera-integration
description: Integrate external and mirrorless cameras into AI Photographer behind vendor-neutral abstractions — CameraAdapter, CameraCapabilities, CameraState, CameraController, FrameSource. Covers capability-driven design, PTP and ImageCaptureCore, Sony Camera Remote SDK and the Sony A7C II reference body, transport selection, connection state, and the licensing constraints that apply to an open-source repository. Use when adding or changing camera vendor support, camera control, live view from an external camera, or the camera bridge. Do not use for the iPhone's own AVFoundation pipeline (use ios-camera).
license: Apache-2.0
metadata:
  project: ai-photographer
  last_verified: "2026-08-15"
  reference_hardware: "Sony ILCE-7CM2 (A7C II)"
---

# External Camera Integration

Reference hardware is a Sony A7C II with Viltrox 35mm and 85mm EVO lenses. **Reference hardware is
not architecture.** Everything here is written so that a Canon, Nikon, Fujifilm, or Panasonic body
is a new adapter, not a new design.

## The central rule

> **The architecture is capability-based, not camera-model-based.**

Core modules never ask *what camera is this*. They ask *what can this camera do*. Model identity
exists in exactly one place: inside a vendor module, for a documented device quirk, with a comment
citing the source.

Forbidden anywhere outside `Camera/Sony/` (or the equivalent vendor directory):

```swift
if cameraModel == "A7C II" { ... }     // no
if vendor == .sony { ... }             // no
```

Required instead:

```swift
guard capabilities.contains(.setAperture) else { return .manualRequest(.aperture) }
```

## Capability model

Capabilities are declared per connected camera, discovered at connect time, and never assumed:

```
liveView               readISO              setISO
readShutterSpeed       setShutterSpeed      readAperture
setAperture            readExposureCompensation
setExposureCompensation                     autofocus
setFocusPoint          triggerShutter       readFocalLength
controlZoom            readFocusPosition    setFocusPosition
downloadPreview        downloadOriginal
```

Three rules:

1. **Read and write are separate capabilities.** A camera that reports aperture may not accept an
   aperture change; a lens may be aperture-controllable on one body and not another.
2. **An absent capability is a product state, not an error.** It becomes a manual-adjustment request
   addressed to the user (`goal.md` §17). The app keeps working.
3. **Capabilities are discovered, not hardcoded per model.** A static per-model table is a fallback
   for values the protocol genuinely cannot report, and lives in the vendor module.

## The protocol boundary

```swift
public protocol CameraAdapter: Sendable {
    var capabilities: CameraCapabilities { get async }
    func readState() async throws -> CameraState
    func apply(_ settings: [CameraSetting]) async -> [SettingResult]
    func triggerAutofocus() async throws
    func capture() async throws -> CaptureResult
}
```

`apply` returns a **result per setting**. Partial success is the normal case: ISO succeeded, aperture
was rejected by the body because it is in the wrong mode, shutter was clamped. Never a single
`throws` that hides which settings landed. The UI needs to show exactly this.

Live view is a `FrameSource`, the same protocol the iPhone camera implements. That is what lets the
vision and guidance layers work identically in both capture modes.

## Transport is separate from adapter

Two independent axes that are easy to conflate:

- **Camera transport** — where the camera is physically attached and how bytes reach it.
- **Director transport** — where the AI planning backend runs.

They are unrelated protocols with unrelated failure modes. A camera bridge outage must not look like
an AI outage, and vice versa.

Sony provides **no iOS build** of the Camera Remote SDK, so on iPhone an external Sony camera
requires a macOS bridge in the path even when no AI is involved. See
[references/transports.md](references/transports.md) for the transport options and their status.

## Connection state is first-class

Model it explicitly and surface it (`ios-ui-design`):

```
disconnected → discovering → connecting → connected → degraded → disconnected
```

`degraded` is real and common: connected but live view dropped, or connected but the body switched to
a mode that refuses remote control. Never infer "connected" from the absence of an error.

## Evidence labels — required

Camera protocol knowledge is full of plausible-sounding claims that are wrong for a specific body.
Every capability claim in this project's docs, comments, and commit messages carries one of:

| Label | Meaning |
|---|---|
| **confirmed** | Verified against official vendor documentation, or observed working on the actual hardware by us. |
| **likely** | Strongly implied by official documentation but not verified on our hardware. |
| **requires hardware verification** | Plausible, unverified, and must be tested before anything depends on it. |
| **unsupported** | Documented as unavailable, or tested and failed. |

Specific rule: **desktop SDK support does not imply iOS support.** Do not write "the app can set
aperture on the A7C II" because the desktop Camera Remote SDK can. That is at best *likely*, via a
bridge, and needs verification.

Community forum posts are never *confirmed*. They may be cited as **empirical/unverified** with a
link, which is genuinely useful for undocumented behavior — just labeled honestly.

## Licensing — read before touching vendor SDKs

This is an open-source repository and the Sony SDK license is restrictive. Two clauses matter most:

- **No redistribution of the SDK.** It may not be committed to this repo in any form.
- **No reverse engineering.** This has consequences beyond the SDK itself, including for
  contributors who also work on independent protocol implementations.

Full analysis and the resulting repository rules are in
[references/licensing.md](references/licensing.md). **Read it before adding any vendor dependency.**

Never commit to this repository: vendor SDK source, headers, or binaries; licensed sample code;
protocol specifications under NDA or restrictive terms; mirrored copies of vendor manuals. Write
original engineering summaries with links to official sources instead — which is what the reference
files in this skill are.

## Development without hardware

Required by `goal.md` §14 and enforced by `opensource-quality`:

- `MockCameraAdapter` is written **first**, before any vendor adapter, and defines the contract.
- Every adapter — mock and vendor alike — passes the *same* conformance test suite.
- Vendor adapters and hardware tests are excluded from ordinary CI.
- A contributor with no camera can implement and test everything above the adapter boundary.

If a vendor adapter needs a capability the mock cannot express, the mock is extended first.

## References

- [references/capability-model.md](references/capability-model.md) — designing and evolving the
  capability set; per-setting result handling.
- [references/transports.md](references/transports.md) — PTP, ImageCaptureCore, USB/UVC, Camera
  Remote SDK, libgphoto2; what runs where.
- [references/sony-a7c2.md](references/sony-a7c2.md) — A7C II specifics with evidence labels and
  open questions.
- [references/licensing.md](references/licensing.md) — Sony license analysis and repository rules.

## Related skills

`ios-camera` (the phone's own pipeline and the shared `FrameSource`), `opensource-quality`
(boundaries, mocks, CI), `photography-director` (exposure intent vs implementation).
