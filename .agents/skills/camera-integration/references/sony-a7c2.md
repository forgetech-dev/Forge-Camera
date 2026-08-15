# Sony A7C II (ILCE-7CM2) — Reference Hardware Notes

**Purpose.** What we believe about the reference body, with honest evidence labels, so nobody builds
on an assumption. This is an original engineering summary — no Sony documentation is reproduced here.

**Last verified:** 2026-08-15. **Nothing in this file has been verified on physical hardware yet.**

---

## Evidence labels

**confirmed** = official vendor documentation or observed by us on the hardware ·
**likely** = strongly implied by official documentation, not verified by us ·
**requires hardware verification** = plausible, untested ·
**unsupported** = documented unavailable or tested and failed

Update labels as verification happens, and record who verified and when.

## Body

| Property | Value | Label |
|---|---|---|
| Model identifier | ILCE-7CM2 | confirmed |
| Sensor | 35mm full-frame, ~33 MP | likely |
| Camera Remote SDK support | Supported; added in SDK v1.10 | likely — confirm against current Sony support matrix |
| PC Remote over USB | Supported | likely |
| PC Remote over Wi-Fi | Supported | likely |
| USB streaming (UVC/UAC) | Supported | likely — resolutions/frame rates require hardware verification |
| USB connector | USB-C | confirmed |

## Capability expectations

Mapped to the project's capability set. **These are expectations to test, not facts to build on.**
Every one of them needs a hardware test before any UI promises it.

| Capability | Expectation | Label |
|---|---|---|
| `liveView` | Available via CrSDK; possibly also via UVC | likely / requires hardware verification |
| `readISO` / `setISO` | Available in PC Remote | likely |
| `readShutterSpeed` / `setShutterSpeed` | Available; constrained by exposure mode | likely |
| `readAperture` / `setAperture` | Available with a compatible lens; depends on exposure mode | requires hardware verification |
| `readExposureCompensation` / `setExposureCompensation` | Available | likely |
| `autofocus` | Triggerable remotely | likely |
| `setFocusPoint` | Available; coordinate convention unknown | requires hardware verification |
| `triggerShutter` | Available | likely |
| `readFocalLength` | Reported for electronically-coupled lenses | requires hardware verification |
| `controlZoom` | Not applicable to prime lenses | unsupported (for the reference lenses) |
| `readFocusPosition` / `setFocusPosition` | Uncertain | requires hardware verification |
| `downloadPreview` | Available after capture | likely |
| `downloadOriginal` | Available; large and slow over Wi-Fi | likely |

### Mode dependence — the thing that will surprise us

Whether a setting is writable depends on the **body's exposure mode**, not only on the camera model.
Aperture is not settable in Shutter Priority; shutter is not settable in Aperture Priority; several
things are locked in Auto. The dial position on a physical body can override remote control at any
moment, without warning.

Design consequences:

- `CameraCapabilities` must be **re-read when camera state changes**, not just at connect. Capability
  is dynamic here.
- A rejected write is a normal outcome and must produce a specific, actionable message — "the body is
  in Shutter Priority; aperture cannot be set remotely" — not a generic failure.
- This is the strongest argument for `apply` returning a per-setting result.

## Reference lenses

| Lens | Notes | Label |
|---|---|---|
| Viltrox 35mm EVO | Third-party AF prime, E-mount | confirmed as reference hardware |
| Viltrox 85mm EVO | Third-party AF prime, E-mount | confirmed as reference hardware |

Third-party lenses are an integration risk worth naming: reported aperture range, focus-position
reporting, and focal-length metadata may differ from Sony first-party glass, and firmware updates
change behavior. Any lens-dependent capability is **requires hardware verification** by default, and
should be verified per-lens, not per-body.

Neither lens zooms, so `controlZoom` is unsupported for this rig. A focal-length *recommendation* from
the AI Director therefore becomes a **lens-change request to the user**, not a camera command — a good
example of why `CameraSetting` results distinguish "applied" from "manual request".

## Known unknowns to resolve first

Ordered by how much they would change the design:

1. **Can USB streaming (UVC) and PC Remote control run simultaneously?** If yes, live view and
   control can be split across two clean channels.
2. **Does an iPhone see the body as an external UVC camera over USB-C?** If yes, the Mac may drop out
   of the live-view path entirely.
3. **What coordinate convention does `setFocusPoint` use?** Needs an explicit conversion at the
   adapter boundary, like every other coordinate hop in this project.
4. **Is focal length reported for the Viltrox lenses?** Determines whether angular guidance works
   automatically or needs manual focal-length entry.
5. **CrSDK live-view latency and frame rate over USB on Apple Silicon**, and whether a native arm64
   build exists.
6. **How quickly do capabilities change** when the mode dial moves, and does the SDK push an event or
   must we poll?

## Verification protocol

When hardware becomes available, verify in this order and record results here with a date:

1. Connect over USB; enumerate; read model and firmware.
2. Read full state; dump every property the transport reports.
3. Read focal length with each reference lens.
4. Start live view; measure resolution, frame rate, and end-to-end latency.
5. Write one exposure parameter in each exposure mode; record which succeed and which are rejected.
6. Trigger autofocus; trigger shutter; retrieve preview; retrieve original; time each.
7. Move the mode dial during a session; observe what the transport reports.

That sequence is deliberately the same as `goal.md` §20's external-camera proof-of-concept checklist.
Results belong in this file, with labels updated from *likely* to *confirmed* or *unsupported*.

## Official sources

- Sony Camera Remote SDK: https://support.d-imaging.sony.co.jp/app/sdk/en/index.html
- Sony A7C II product and Help Guide (via Sony support; consult the official Help Guide for the body
  rather than any mirrored copy)
- Sony Camera Remote Toolkit: https://support.d-imaging.sony.co.jp/app/cameraremotecommand/en/index.html

## Redistribution note

Do not copy Sony Help Guide text, SDK documentation, protocol tables, or constant definitions into
this repository. Summarize in original words and link. See [licensing.md](licensing.md).
