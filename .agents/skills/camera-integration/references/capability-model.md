# Capability Model — Design Reference

**Purpose.** How `CameraCapabilities`, `CameraState`, `CameraSetting`, and `SettingResult` are shaped
and evolved, so vendor differences stay inside vendor modules.

**Last verified:** 2026-08-15.

---

## Why capabilities instead of models

There are hundreds of camera bodies and each firmware revision changes behavior. A model-based design
needs a table that is always out of date and a `switch` that grows forever. A capability-based design
needs each adapter to answer one question honestly: *what can I do right now?*

The core never branches on identity. It branches on ability.

## The four types

```swift
struct CameraCapabilities: Sendable {          // what this camera can do, now
    func contains(_ capability: Capability) -> Bool
}

struct CameraState: Sendable {                 // what this camera is doing, now
    let iso: ISOValue?
    let shutterSpeed: ShutterSpeed?
    let aperture: Aperture?
    let exposureCompensation: EV?
    let focalLength: Millimeters?
    let exposureMode: ExposureMode?
    // every field optional: absent means "not reported", never "zero"
}

enum CameraSetting: Sendable { case iso(ISOValue), aperture(Aperture), ... }

enum SettingResult: Sendable {
    case applied(CameraSetting)
    case clamped(requested: CameraSetting, actual: CameraSetting)
    case rejected(CameraSetting, reason: RejectionReason)
    case unsupported(CameraSetting)
}
```

**Optionality is meaning.** A `nil` aperture means the camera did not report one. It never means
f/0. Same rule as the AI plan contract in `photography-director` — absent is "no information", not a
default value. Getting this wrong produces confidently wrong guidance.

## Capabilities are dynamic

The instinct is to read capabilities once at connect and cache them. That is wrong for real cameras:
turning the mode dial changes what is writable, and it happens mid-session without notice.

Rules:

- Re-read capabilities when `CameraState` changes materially, or on an explicit event if the
  transport provides one.
- Treat capability as a *snapshot*, not a constant. `capabilities` is `async` for this reason.
- A write that was legal a second ago may be rejected now. That is not a bug; handle it.

## `clamped` deserves its own case

Cameras silently snap values to their supported set — request ISO 1234, get ISO 1250. Folding that
into `applied` loses information the UI needs, and folding it into `rejected` is wrong because the
setting did change. A distinct `clamped` case lets the interface show what actually happened, and
lets the exposure engine reason about the real value rather than the requested one.

## Rejection reasons must be actionable

```swift
enum RejectionReason: Sendable {
    case wrongExposureMode(current: ExposureMode)   // "body is in Shutter Priority"
    case outOfRange(supported: ClosedRange<...>)
    case lensDoesNotSupport
    case cameraBusy
    case notPermittedInCurrentState
}
```

A generic failure produces a generic message, and a generic message about a camera setting is
useless. The user needs to know whether to turn a dial, change a lens, or wait.

## Adding a new capability

1. Does an existing capability cover it? Prefer widening semantics over adding an entry.
2. Add the case to `Capability`.
3. Extend `MockCameraAdapter` **first**, including its failure modes.
4. Add it to the shared adapter conformance test suite.
5. Implement in the vendor adapter.
6. Handle absence in the UI — an unsupported capability must degrade to a manual request or a hidden
   control, never a dead button.

Step 3 before step 5 is the important ordering. If the mock cannot express it, the abstraction is not
finished.

## Shared conformance suite

Every adapter — mock, Sony, and any future vendor — runs the same test suite. It asserts contract
properties, not values:

- Declared capabilities match actual behavior: if `setISO` is declared, an in-range ISO write must
  not return `unsupported`.
- Undeclared capabilities always return `unsupported`, never throw.
- `apply` returns exactly one result per requested setting, in order.
- `readState` after a successful `apply` reflects the change (or the clamped value).
- Reads never mutate camera state.
- Disconnection mid-operation produces a typed error, not a hang.

This suite is the real definition of `CameraAdapter`. The protocol declaration is just the syntax.

## Anti-patterns

- `CameraCapabilities` as an `OptionSet` of static per-model flags. Convenient, and wrong the moment
  the mode dial moves.
- A `CameraManager` that owns discovery, connection, control, state, and UI notification. Explicitly
  called out in `goal.md` §23.
- Vendor enums leaking into the core (`SonyExposureMode` in a shared type). Convert at the adapter
  boundary.
- `apply` that throws on first failure — the caller loses the results of the settings that succeeded.
- Booleans for tri-state facts. "Can set aperture" has at least three answers: yes, not in this mode,
  and not with this lens.

## Open questions

- Should capability changes be a push stream (`AsyncStream<CameraCapabilities>`) rather than
  re-reads? Depends on whether transports provide change events — see `sony-a7c2.md`.
- Does focus-point coordinate space need its own capability, given vendors may differ in convention?
