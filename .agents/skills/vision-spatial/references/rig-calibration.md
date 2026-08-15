# Rig Calibration — Principles, Not Yet an Implementation

**Purpose.** In External Camera Mode the iPhone may be rigidly mounted to a mirrorless body. The
phone has metric tracking; the mirrorless camera has the good image. Combining them requires knowing
the fixed transform between them. This file records the principles so the design stays open — it is
**not** a specification to build now.

**Status:** design guidance only. Do not build a calibration system until External Camera Mode
actually works end-to-end without one.

**Last verified:** 2026-08-15.

---

## The problem

ARKit reports the pose of the **iPhone's** camera. Photographer-movement guidance derived from it
describes where the phone went. If the phone is in the user's pocket, or hand-held while the Sony sits
on a tripod, that has nothing to do with the photograph.

Three distinct situations:

| Situation | Coupling | Metric photographer guidance |
|---|---|---|
| Phone Camera Mode | `.rigid` (trivially — same device) | Yes |
| External camera, phone hand-held | `.decoupled` | **No** — relative cues only |
| External camera, phone mounted on the rig | `.rigid`, after calibration | Yes, within calibration accuracy |

## The rule that ships now

`MotionCoupling` is declared explicitly at the composition root:

```swift
enum MotionCoupling: Sendable { case rigid, decoupled, unknown }
```

`GuidanceEngine` refuses to emit `.metric` photographer cues unless coupling is `.rigid`. `.unknown`
behaves as `.decoupled` — fail safe toward honesty. A user claiming a rigid mount must do so
explicitly; it is never inferred.

This costs almost nothing to implement now and makes the whole category of "confidently wrong metric
guidance" impossible. `MotionSource` is a separate protocol from `FrameSource` for exactly this
reason.

## What calibration would need to establish

The rigid-body transform `T_phone→camera`: a rotation and a translation between the phone camera's
optical frame and the external camera's optical frame.

Complications that make this non-trivial:

- **Optical axes differ.** The phone and the mirrorless body point in nearly, but not exactly, the
  same direction. A 2° error at 5 m is ~17 cm of lateral error — larger than the guidance precision
  being claimed.
- **Field of view differs**, and changes with the external lens. An 85mm view is a small crop of the
  phone's view; a 35mm view is closer but still different.
- **Entrance pupils are in different places**, so the translation component is real, not negligible,
  and it changes with lens.
- **Mounts flex.** A cold-shoe phone clamp is not a rigid body under real handling.
- **Per-lens, per-mount.** The transform is a property of a *configuration*, not of a phone.

## Principles for an eventual implementation

1. **Explicit, user-initiated calibration.** Never inferred silently. The user says "I have mounted
   the phone", performs a procedure, and gets a result they can see.
2. **A concrete procedure with a measurable residual.** For example, both cameras observe the same
   distinctive target from several viewpoints; solve for the transform; report the reprojection
   error. A calibration with no error metric is a guess with extra steps.
3. **Validate, then trust.** Reject a calibration whose residual exceeds a threshold rather than
   accepting a bad one. A bad calibration is worse than none, because it produces confident numbers.
4. **Persist per configuration** — keyed by phone model + mount + external body + lens — and
   invalidate when any of those change.
5. **Continuous plausibility checking.** If the two views disagree about the scene during use (the
   subject is not where the transform predicts), demote coupling to `.decoupled` and tell the user.
   Mounts slip.
6. **Calibration confidence flows into `Measured.confidence`.** A marginal calibration should widen
   uncertainty and eventually cross the threshold back to relative cues — the same mechanism used
   everywhere else, not a special case.
7. **Degrade, never fail.** No calibration means relative guidance, which is still a working product.

## Simpler intermediate steps

Before full extrinsic calibration, cheaper things that deliver most of the value:

- **Rotation-only calibration.** Aligning optical axes is much easier than solving full 6-DoF, and
  angular guidance (level, tilt, pan) is where the free accuracy is anyway.
- **Scale-only.** If the phone's ARKit translation is trusted for *direction* but the transform is
  unknown, relative magnitudes still work — that is already the `.decoupled` behavior, and it is
  usually enough.
- **User-declared offset.** "Phone is mounted above the camera, roughly 8 cm." Crude, honest, and
  vastly better than nothing — as long as the resulting confidence reflects how crude it is.

## Anti-patterns

- Assuming the transform is identity because both cameras "point the same way".
- Calibrating once and trusting it forever across mount removals.
- Presenting calibrated metric guidance without reflecting calibration error in the confidence.
- Building the calibration system before External Camera Mode works at all — `goal.md` §13's
  no-premature-abstraction rule applies with full force here.

## Official sources

- ARKit `ARCamera` (transform, intrinsics, tracking state):
  https://developer.apple.com/documentation/arkit/arcamera
- Camera calibration theory: standard pinhole + distortion models (Zhang's method is the usual
  reference). Apple provides no first-party multi-camera extrinsic calibration API.

## Open questions

- Is a phone-to-camera mount rigid enough in practice for metric claims at all? **Requires hardware
  verification** — and if the answer is no, this entire document resolves to "always `.decoupled`",
  which would be a perfectly good outcome.
- Would a simple rotation-only calibration deliver most of the value at a fraction of the complexity?
- Can the two views be automatically cross-checked using the subject detected in both, giving
  continuous validation for free?
