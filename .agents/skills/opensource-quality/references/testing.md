# Testing Strategy — Project Reference

**Purpose.** How AI Photographer stays testable without hardware, without API keys, and without
network — and how the parts that genuinely need those get isolated.

**Last verified:** 2026-08-15. Swift 6.0 toolchain; Swift Testing ships with Xcode 16.

---

## The contributor promise

> `make build && make test` is green on a clean clone, with no camera, no lens, no API key, no
> subscription, and no network.

Every design decision below serves that. It is the difference between a project people can contribute
to and a project only its author can build.

## Test tiers

| Tier | Covers | In ordinary CI |
|---|---|---|
| **Unit** | Guidance engine, exposure engine, plan validation, capability handling, scene-change scoring, coordinate conversions, heuristic director | Yes |
| **Integration** | frame → `SceneState`; `SceneState` → plan (mock provider); plan → guidance; `CameraController` → `MockCameraAdapter` | Yes |
| **Replay** | Full pipeline over recorded sessions, golden-file comparison | Yes |
| **Property** | Invariants that must hold for all inputs | Yes |
| **Hardware** | Real camera: connect, live view, read, write, shutter, retrieve | **No** — explicitly invoked |
| **External service** | Real AI provider round-trips | **No** — explicitly invoked |

Hardware and external-service tests are **skipped, not absent**. They stay compiled so they cannot rot:

```swift
@Test(.enabled(if: ProcessInfo.processInfo.environment["FORGE_HARDWARE_TESTS"] == "1"))
func capturesOnRealCamera() async throws { ... }
```

Run them with a dedicated make target, never as part of `make test`.

## Test doubles

Written **before** the real implementation, because writing the mock first is what proves the
abstraction is right. If the mock cannot express a behavior, the protocol is not finished.

| Double | Role |
|---|---|
| `MockCameraAdapter` | Configurable capabilities and failure modes. Defines the `CameraAdapter` contract. |
| `MockDirectorProvider` | Returns fixture plans, including invalid ones. Deterministic. |
| `RecordedFrameSource` | Replays recorded frames at recorded timestamps. |
| `ReplayCameraAdapter` | Replays a recorded camera interaction, including rejections. |
| `RecordedSession` | The bundle format below. |

**Mocks must be able to fail.** A mock that only succeeds tests the happy path and nothing else. The
valuable ones simulate: capability absent, setting rejected because of exposure mode, value clamped,
disconnect mid-operation, timeout, malformed plan, and slow response.

## Shared conformance suites

Every `CameraAdapter` — mock and vendor — runs one shared suite asserting contract properties, not
values. Same for `DirectorProvider` and `FrameSource`. See `camera-integration` →
`references/capability-model.md` for the camera suite's contents.

This suite is the real definition of the protocol; the declaration is only syntax.

## Recorded sessions and replay determinism

```
Fixtures/sessions/portrait-backlit-01.forgesession/
├── manifest.json     device, camera, lens, focal length, coupling, schema version, Vision revisions
├── frames.jsonl      { index, timestamp, file, orientation }
├── frames/0000.jpg …
├── motion.jsonl      optional: gravity, ARKit pose per timestamp
├── director.jsonl    recorded plan requests + responses (replay with no AI)
└── golden.json       expected GuidanceState sequence
```

Replay feeds frames at recorded timestamps through the real pipeline with recorded director
responses, and diffs the resulting `GuidanceState` sequence against `golden.json`.

This is exactly reproducible **only because** the engines are pure and time is injected. That is what
the purity rule in the parent skill buys: a regression net for tuning smoothing, deadband, and
hysteresis constants, where a change in behavior shows up as a readable diff.

Record `manifest.json` carefully — Vision request revisions and OS version matter, because an OS
update can legitimately change detections and invalidate a golden file. When that happens the golden
is regenerated deliberately, with the diff reviewed, not silently overwritten.

Session fixtures are binary and grow. Use **git-lfs from the first commit**; retrofitting it is
painful.

## Property tests

Invariants worth asserting for all inputs:

- Normalized coordinates stay in `[0,1]` through every transform.
- Coordinate round-trips are identity within epsilon (use asymmetric fixtures — a centered square
  passes broken code).
- No `.metric` cue is ever emitted when motion coupling is not `.rigid`.
- No `.metric` cue is ever emitted from a `.estimated`-provenance measurement.
- Cue count never exceeds the policy budget.
- Hysteresis never oscillates on a monotonically improving input.
- Plan validation never produces out-of-range values, whatever the input.
- Validation never crashes — on `NaN`, on empty objects, on adversarial strings.

## Determinism rules for CI

- No network. A test that hits a network is not a unit test.
- No wall-clock dependence. Inject time; never `Date()` in a code path under test.
- No randomness without a seed.
- No dependence on device capabilities. Ordinary tests run on any machine, including a headless CI
  runner and the simulator.
- No shared mutable state between tests.

## CI

1. `make check` — format, lint, build, test.
2. Simulator build of the app target, proving it still links.
3. **Boundary guard** — grep for vendor identifiers outside their owning modules and for imports
   violating the module graph. ~20 lines; the difference between agreed layering and enforced layering.
4. **Secret guard** — scan for committed credentials.

CI never touches a camera, an API key, or a paid endpoint.

## Pitfalls

- Testing the mock instead of the code (asserting that `MockCameraAdapter` returns what it was
  configured to return proves nothing).
- Golden files regenerated automatically on failure — that turns a regression net into a rubber stamp.
- Hardware tests that quietly run in CI because a variable leaked into the environment.
- Performance assertions in ordinary tests; CI machines vary. Measure performance deliberately, on
  device (`ios-camera` → performance.md).
- Mocks that drift from real adapter behavior — the shared conformance suite is the defense.

## Official sources

- Swift Testing: https://developer.apple.com/documentation/testing
- Swift Package Manager: https://www.swift.org/documentation/package-manager/
- XCTest (still valid where needed): https://developer.apple.com/documentation/xctest

## Open questions

- Golden-file tolerance: exact equality is the strongest signal but brittle against floating-point
  and OS drift. An epsilon comparison on numeric fields with exact matching on discrete fields is
  probably right — decide when the first replay test exists.
- Whether recorded sessions should store raw frames or pre-computed `SceneState`s. Raw exercises more
  of the pipeline; pre-computed is smaller and immune to Vision revision changes. Possibly both.
