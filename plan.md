# AI Photographer — Implementation Plan

**Status:** draft v1 · **Companion to:** [`goal.md`](./goal.md)

`goal.md` says *why* and *what success looks like*. This document says *what must be true*, *how it is
built*, and *in what order*. Where `goal.md` is ambiguous, this document makes the binding decision
and marks it **[DECISION]**. Where a fact must be checked against real hardware or a vendor SDK
before it can be relied on, it is marked **[VERIFY-n]** and collected in §12.

Once the repo has real code, §4–§6 should be extracted into `ARCHITECTURE.md`, §3 into
`REQUIREMENTS.md`, and §11 into `CONTRIBUTING.md` + `AGENTS.md`. Until then, one document is easier
to keep honest than five.

---

## 1. Naming and Scope

**[DECISION]** Product name: *AI Photographer*. Code namespace / module prefix: `Forge`. Repo:
`Forge-Camera`. Bundle id root: `dev.forge.photographer` (placeholder until a domain is chosen).

The word "Forge" appears only in module and type-prefix positions. No user-facing string depends on
it, so the product name can change without a code migration.

---

## 2. Verified Environment Baseline

Checked on this machine, 2026-08-15:

| Tool | Version | Consequence for the plan |
|---|---|---|
| macOS | 15.0.1 (arm64) | Server target may assume Apple Silicon; keep x86_64 build unbroken but untested |
| Xcode | 16.0 (16A242d) | Swift Testing bundled; synchronized folder groups available in `.xcodeproj` |
| Swift | 6.0 | Swift 6 language mode + strict concurrency available from day one |
| iOS SDK | 18.0 | New Vision Swift API (`ImageRequestHandler`, async requests) available |
| Make | GNU Make 3.81 | Apple's ancient build; **use portable Makefile syntax only** — no `$(file …)`, no `.ONESHELL` |
| git | 2.39.5 | fine |
| `gh` | **not installed** | needed for CI/PR automation → add to `make bootstrap` |
| `codex` | 0.144.6 | first Director backend can shell out to `codex exec` |
| `libusb` | installed | a `libgphoto2` PTP path is viable on this machine without new system deps |

**[DECISION]** Deployment targets: **iOS 18.0**, **macOS 15.0**.

Rationale: iOS 18 unlocks the modern Vision Swift API, which is `async`/`Sendable`-native and avoids
wrapping completion-handler `VNRequest` code in Swift 6 strict-concurrency mode. That saves a
meaningful amount of boilerplate in the single most performance-sensitive module. Cost: excludes
iOS 17 devices. For a project at phase 0 with no users, that is the right trade. Revisit before the
first public TestFlight build.

---

## 3. Requirements

IDs are stable and referenced from phase exit criteria and (later) from commit messages and tests.

### 3.1 Functional — Core Loop

| ID | Requirement | Phase |
|---|---|---|
| F-01 | Deliver live frames from a `FrameSource` at ≥15 FPS without unbounded queuing | 2 |
| F-02 | Produce a `SceneState` per analyzed frame: subjects, poses, horizon, lighting, motion | 2 |
| F-03 | Track subjects across frames with stable identities | 2 |
| F-04 | Request a `CompositionPlan` from a `DirectorProvider` on an explicit trigger policy, never per-frame | 3 |
| F-05 | Validate every plan against a versioned schema; reject or partially degrade invalid plans | 3 |
| F-06 | Compute a `GuidanceState` locally from (`SceneState`, `CompositionPlan`) at frame rate | 1 |
| F-07 | Render photographer / subject / camera cues with stable, non-flickering output | 2 |
| F-08 | Signal readiness when the current state is within tolerance of the plan | 2 |
| F-09 | Capture a still image and retrieve it at full quality | 4 |
| F-10 | Review a captured image and produce a `ReviewResult` with concrete defects | 4 |
| F-11 | Convert a `ReviewResult` into a retake `CompositionPlan` | 4 |

### 3.2 Functional — Camera

| ID | Requirement | Phase |
|---|---|---|
| F-20 | Phone Camera Mode works end-to-end with no external hardware and no network | 2 |
| F-21 | Every camera exposes a `CameraCapabilities` value; no control is attempted unless declared | 5 |
| F-22 | External Camera Mode: connect, live view, read state, read focal length, set ≥1 exposure parameter, trigger shutter, retrieve preview | 5 |
| F-23 | Three control levels — Recommend / Ask Before Apply / Full Auto — with **Ask Before Apply** as default | 6 |
| F-24 | Applying settings is transactional: report per-setting success/failure, never silently partially apply | 6 |
| F-25 | Computational modes (bracket, stack, panorama, timelapse) are optional modules recommended by the Director | 7 |

### 3.3 Functional — Degradation (each is a testable behavior, not a fallback comment)

| ID | Requirement |
|---|---|
| F-30 | No AI backend → live view, local heuristic director, composition guides, camera control all still work |
| F-31 | No ARKit / no depth → guidance emits **directional** cues only; metric units are structurally unrepresentable |
| F-32 | Unknown focal length → user can enter it manually; angular math falls back to directional |
| F-33 | Unsupported setting write → cue becomes a manual-adjustment request addressed to the user |
| F-34 | No live view but retrievable images → post-shot review mode remains available |
| F-35 | Any single subsystem failure degrades only its own cues; the app stays usable |

### 3.4 Non-Functional

| ID | Requirement | Budget / Rule |
|---|---|---|
| N-01 | Perception latency | frame → `SceneState` ≤ 33 ms p95 on iPhone 14 Pro class hardware |
| N-02 | Guidance latency | `SceneState` → `GuidanceState` ≤ 5 ms p95, main-thread-free |
| N-03 | Planning latency | request → validated plan ≤ 3 s p95; UI never blocks on it |
| N-04 | Planner rate | ≤ 2 Hz hard cap, ≤ 0.2 Hz typical, single in-flight request |
| N-05 | Bandwidth | no continuous video upload, ever; images only on plan/review requests |
| N-06 | Core purity | `ForgeCore` imports only `Foundation`; enforced by the module graph, not by review |
| N-07 | Vendor isolation | zero occurrences of `Sony`/`Canon`/`Codex`/`OpenAI` outside their own modules; enforced by a CI grep |
| N-08 | Hardware-free dev | `make build && make test` green on a clean clone with no camera, no API key, no network |
| N-09 | Determinism | replay of a recorded session produces byte-identical `GuidanceState` sequences |
| N-10 | Secrets | never in source, git, logs, `UserDefaults`, analytics, or crash reports; Keychain only |
| N-11 | Concurrency | Swift 6 language mode, strict concurrency, zero `@unchecked Sendable` without a written justification comment |
| N-12 | Headless | build, test, install-to-device, and archive all runnable over SSH |

---

## 4. Architecture

### 4.1 The two independent remote axes

`goal.md` §10 describes a replaceable *AI* backend. There is a second, unrelated network hop that
must not be conflated with it: **where the camera physically lives**. Sony ships no iOS build of its
Camera Remote SDK **[VERIFY-1]**, so External Camera Mode on iPhone requires a Mac in the path even
when the AI runs on-device or not at all.

```
        ┌───────────────── iPhone app ─────────────────┐
        │  FrameSource ──▶ Vision ──▶ SceneState       │
        │       ▲                        │             │
        │       │                        ▼             │
        │  CameraAdapter          GuidanceEngine ──▶ UI │
        └───────┼────────────────────────┼─────────────┘
                │ camera transport        │ director transport
                │ (axis A)                │ (axis B)
        ┌───────▼──────────┐      ┌───────▼──────────────────┐
        │ macOS bridge     │      │ Director backend          │
        │  Sony adapter    │      │  Mac+Codex / cloud /      │
        │  USB / PTP       │      │  BYOK / self-hosted /     │
        └───────┬──────────┘      │  on-device model          │
                │                 └───────────────────────────┘
             Camera
```

Both axes happen to terminate on the same Mac in the phase-5 development setup. They are separate
protocols, separate ports, separate failure modes, and separate config. Conflating them is the
single most likely architectural mistake in this project.

### 4.2 The three-rate pipeline

```
FrameSource            15–60 Hz   ─┐
  └─ SceneAnalyzer     15–60 Hz    │ local, on-device, never leaves the phone
       └─ SceneTracker 15–60 Hz    │
            ├─ GuidanceEngine  = frame rate ─▶ UI 30–60 Hz
            └─ PlanTrigger ── 0.2–2 Hz ─▶ DirectorProvider ─▶ CompositionPlan
                                                                   │
                              ◀────── latched, reused every frame ──┘
```

The `CompositionPlan` is **latched state**, not an event stream. Guidance reads whatever the current
plan is, every frame. A slow, failed, or absent plan never stalls the guidance loop — it just means
guidance runs against the previous plan or against the heuristic director's plan.

### 4.3 Module graph

Modules are SwiftPM targets. They exist for one reason: **the compiler, not a reviewer, enforces
N-06 and N-07**. Arrows are the only permitted dependencies.

```
                      ┌──────────────┐
                      │  ForgeCore   │  Foundation only. Domain types + engines.
                      └──────┬───────┘
        ┌──────────────┬─────┴──────┬──────────────┬───────────────┐
        ▼              ▼            ▼              ▼               ▼
  ForgeVision    ForgeCapture  ForgeDirector  ForgeBridge    ForgeTestSupport
  Vision/ARKit/  AVFoundation   HTTP client   wire types      mocks, fixtures,
  CoreMotion     FrameSource    + providers   (shared)        session replay
        │              │            │              │
        └──────────────┴─────┬──────┴──────────────┘
                             ▼
                    ForgePhotographer (iOS app, SwiftUI)

  macOS side (never linked into the iOS app):
    forge-server (executable) ─▶ ForgeBridge, ForgeCore, ForgeCameraSony, ForgeDirectorCodex
```

| Module | Owns | Must not import |
|---|---|---|
| `ForgeCore` | `SceneState`, `CompositionPlan`, `GuidanceState`, `CameraCapabilities`, `ExposurePlan`, `GuidanceEngine`, `ExposureEngine`, `PlanTrigger`, `HeuristicDirector`, all protocols | anything but `Foundation` |
| `ForgeVision` | `VisionSceneAnalyzer`, subject tracking, horizon estimation, `ARMotionSource` | camera vendors, networking, SwiftUI |
| `ForgeCapture` | `AVFoundationFrameSource`, `PhoneCameraAdapter` | Vision, networking, SwiftUI |
| `ForgeDirector` | `HTTPDirectorProvider`, plan decoding + validation, retry/budget policy | Vision, AVFoundation, SwiftUI |
| `ForgeBridge` | wire DTOs + endpoint paths shared by app and server | everything else except `ForgeCore` |
| `ForgeCameraSony` | Sony `CameraAdapter`, CrSDK/PTP glue | `ForgeVision`, UI, `ForgeDirector` |
| `ForgeDirectorCodex` | `codex exec` invocation, prompt assembly, schema coercion | app-side modules |
| `ForgeTestSupport` | `MockCameraAdapter`, `RecordedFrameSource`, `MockDirectorProvider`, fixtures, golden-file helpers | production modules other than `ForgeCore` |
| `ForgePhotographer` | SwiftUI views, view models, composition root, DI wiring | nothing vendor-specific; talks only to protocols |

**Composition root.** Exactly one place constructs concrete types and injects them:
`ForgePhotographer/App/CompositionRoot.swift`. Everything else receives protocols through
initializers. No service locator, no DI framework, no singletons (`goal.md` §13).

### 4.4 The five protocols

Everything pluggable goes through one of these. If a new abstraction is proposed, it must justify
why it is not one of these five.

```swift
public protocol FrameSource: Sendable {
    var frames: AsyncStream<SceneFrame> { get }   // latest-wins, buffer of 1
    func start() async throws
    func stop() async
}

public protocol CameraAdapter: Sendable {
    var capabilities: CameraCapabilities { get async }
    func readState() async throws -> CameraState
    func apply(_ settings: [CameraSetting]) async -> [SettingResult]  // per-setting result, F-24
    func triggerAutofocus() async throws
    func capture() async throws -> CaptureResult
}

public protocol DirectorProvider: Sendable {
    func plan(_ request: DirectorRequest) async throws -> CompositionPlan
    func review(_ request: ReviewRequest) async throws -> ReviewResult
}

public protocol SceneAnalyzer: Sendable {
    func analyze(_ frame: SceneFrame, previous: SceneState?) async -> SceneState
}

public protocol MotionSource: Sendable {
    var pose: DevicePose? { get async }            // metric only when tracking is healthy
    var gravity: Vector3 { get async }
}
```

`MotionSource` is deliberately separate from `FrameSource`. See §6.5 — this separation is what makes
F-31 enforceable.

---

## 5. Core Contracts

### 5.1 Coordinate and unit conventions — normative

Every ambiguity here is a future bug. These are binding.

- **Forge normalized frame space**: origin **top-left**, x → right, y → down, both in `[0, 1]`,
  measured on the **orientation-corrected, as-displayed** image.
  Vision returns bottom-left-origin coordinates; AVFoundation metadata uses another convention.
  **Every adapter converts at its own boundary.** `ForgeCore` never sees a foreign convention, and
  each adapter has a round-trip conversion test.
- **Angles**: degrees, `Double`. Positive = **counter-clockwise viewed along the negative axis**
  (right-hand rule). `bodyYaw = 0` means the subject faces the camera.
- **Distances**: **meters**, SI, everywhere internally. Centimeters, feet, and inches exist only in
  the presentation layer's formatter. No exceptions.
- **Time**: monotonic seconds (`TimeInterval`) from a single clock captured at frame acquisition.
  Never wall-clock, never `Date()` in the pipeline.
- **Subject height**: `targetHeight` is the subject's bounding-box height **as a fraction of frame
  height**.
- **`camera.heightAdjustment`**: **[DECISION]** — `goal.md` §4's example leaves the unit undefined.
  It is a **fraction of the subject's on-screen height**, dimensionless. So `-0.15` means "lower the
  camera by 15% of the subject's height". This is scale-free, so the Director can produce it from a
  single image with no metric knowledge, and it converts to centimeters only when the subject's real
  height is independently known. A metric field would have forced the AI to guess a scale it cannot
  see.

### 5.2 `SceneState`

```swift
public struct SceneState: Sendable, Equatable, Codable {
    public let timestamp: TimeInterval
    public let frame: FrameGeometry              // pixel size, aspect, applied orientation
    public let subjects: [DetectedSubject]       // sorted by salience, descending
    public let horizon: HorizonEstimate?         // normalized y + roll degrees + confidence
    public let lighting: LightingEstimate?       // luma percentiles, clipped-highlight/shadow fraction
    public let motion: DeviceMotionState?        // gravity, roll/pitch, optional metric pose
    public let depth: DepthSummary?              // near/far/subject distance, all optional + confidence
    public let camera: CameraState?              // focal length, aperture, ISO, shutter, capability snapshot
}

public struct DetectedSubject: Sendable, Equatable, Codable {
    public let id: SubjectID                     // stable across frames (F-03)
    public let bounds: NormalizedRect
    public let kind: SubjectKind                 // .person, .animal, .object(label)
    public let pose: BodyPose?                   // normalized joints + per-joint confidence
    public let faceOrientation: FaceOrientation? // yaw/pitch/roll degrees + confidence
    public let distance: Measured<Double>?       // meters — only when genuinely measured
    public let salience: Double                  // 0…1
}
```

`Measured<T>` carries a value **and** a confidence and a provenance (`.lidar`, `.arkit`,
`.estimated`, `.userProvided`). Anything without provenance cannot be rendered with units.

### 5.3 `CompositionPlan` — the AI contract

Wire format (`schemaVersion: 1`). All fields except `schemaVersion`, `planId`, and `intent` are
**optional, and absent means "no opinion" — never "zero"**. This distinction is load-bearing: a
missing `heightAdjustment` must not become a "hold your position" cue.

```json
{
  "schemaVersion": 1,
  "planId": "6f1c…",
  "requestId": "a92e…",
  "intent": "environmental_portrait",
  "confidence": 0.82,
  "rationale": "Backlit subject; place off-center to include the archway.",
  "subject":  { "targetX": 0.64, "targetY": 0.48, "targetHeight": 0.66,
                "bodyYaw": -20, "headYaw": 5, "poseHint": "weight_on_back_foot" },
  "scene":    { "targetHorizon": 0.34, "avoidRegions": [[0.0,0.0,0.2,0.4]] },
  "camera":   { "heightAdjustment": -0.15, "yawAdjustment": 7,
                "recommendedFocalLength": 35 },
  "exposure": { "priority": "subject", "apertureHint": 2.8, "minShutterDenominator": 250 },
  "capture":  { "kind": "bracket", "stops": [-2, 0, 2] },
  "expiresAfterSeconds": 20
}
```

**Validation rules** (`ForgeCore`, pure, unit-tested — implements F-05):

1. Reject the whole plan if `schemaVersion` major differs, or `planId`/`intent` is missing.
2. **Field-level degradation otherwise.** An out-of-range `targetX` drops *that field*, logs a
   validation warning, and the rest of the plan survives. A plan is not all-or-nothing.
3. Clamp normalized values to `[0,1]`; reject `NaN`/`±inf`; wrap angles to `(-180, 180]`.
4. Snap `recommendedFocalLength` to the connected lens/camera's declared range; drop it if the
   focal length is unknown and no manual value was entered.
5. Unknown enum cases (`intent`, `poseHint`, `capture.kind`) decode to `.unknown(String)` and are
   ignored by engines — forward compatibility without a schema bump.
6. Unknown top-level keys are ignored, never an error.
7. **`rationale` is display-only.** It is `String?`, it is shown to the user, and **no engine, no
   view model, and no test may branch on its content.** This is the concrete enforcement of
   `goal.md` §23's "free-text AI responses used as application state".

**Provider-side generation.** Each `DirectorProvider` is responsible for getting valid JSON out of
its own model — structured output / JSON-schema-constrained decoding where available, low
temperature, and at most **one** repair retry with the validation error appended to the prompt. If
the repair fails, the provider throws and the previous plan stays latched (F-30 path). No repair
loops, no "just parse whatever came back".

### 5.4 `GuidanceState` — false precision is a type error

```swift
public enum GuidanceMagnitude: Sendable, Equatable {
    case metric(meters: Double, confidence: Double)
    case relative(Relative)                       // .slight, .moderate, .large
    public enum Relative: Sendable { case slight, moderate, large }
}

public struct GuidanceCue: Sendable, Equatable {
    public let actor: GuidanceActor                // .photographer, .subject, .camera
    public let axis: GuidanceAxis                  // .left/.right/.up/.down/.forward/.back/.rotate/.tilt/.focalLength/.setting
    public let magnitude: GuidanceMagnitude
    public let priority: Int
    public let manualRequest: Bool                 // true when the app cannot do it itself (F-33)
}

public struct GuidanceState: Sendable, Equatable {
    public let planId: String?
    public let cues: [GuidanceCue]                 // pre-sorted, pre-filtered
    public let readiness: Readiness                // .blocked(GuidanceCue) / .close / .ready
    public let overlay: OverlayModel               // target box, thirds, horizon line, avoid regions
}
```

There is **no** `Double` distance field on `GuidanceCue`. A cue built without metric provenance
*cannot* carry meters, so the renderer cannot print "40 cm" (F-31, `goal.md` §5). The formatter
switches on the enum; `.relative` renders as "Move left" / "Move left a bit" / "Move well left".

---

## 6. Algorithms and Policies

All tunable constants live in one file per engine — `GuidancePolicy.swift`, `ExposurePolicy.swift`,
`PlanTriggerPolicy.swift` — as a `struct` with a `.default` static. No magic numbers scattered
through logic; every constant is named and adjustable from one place, which also makes them
sweepable in replay tests.

### 6.1 Framing decomposition — the rotate-vs-step decision

Moving the subject left in the frame can be achieved by panning right *or* by stepping right. These
are **not** equivalent: translation changes perspective and background relationships, rotation does
not. The engine needs an explicit policy, in this priority order:

1. **Subject size error → dolly (translation along the optical axis).** Never fixed by zooming
   unless the plan explicitly changed `recommendedFocalLength`.
2. **Subject position error → pan/tilt (rotation).** Cheapest correction, preserves perspective.
3. **`scene.avoidRegions` violations / background conflicts → lateral translation.** This is the
   only thing lateral stepping is for; it is what actually moves a distracting object off the
   subject's head.
4. **`camera.heightAdjustment` → vertical translation.**
5. **`camera.recommendedFocalLength` → focal length change** (lens swap or zoom cue).

### 6.2 Angular math (pinhole model)

With horizontal field of view `θ_h` derived from focal length and sensor width:

```
yaw(x)  = atan( (2x − 1) · tan(θ_h / 2) )
Δyaw    = yaw(x_target) − yaw(x_current)
```

and the same form on `y` with `θ_v` for tilt. This is exact for a pinhole camera and needs only
focal length + sensor dimensions, both of which are in `CameraCapabilities`. **If either is unknown,
the cue degrades to `.relative`** — this is the concrete mechanism behind F-32.

### 6.3 Dolly without knowing anything metric

Subject on-screen height `s` scales as `1/d` for a fixed focal length. Therefore:

```
d_target / d_current = s_current / s_target
```

The subject's real-world height **cancels out**. So the engine can always compute the *ratio* of the
move — "you need to be at 80% of your current distance" — from image data alone, and map that to a
`.relative` magnitude. Metric scale is needed **only** for the final unit conversion:

```
Δd = d_current · (s_current / s_target − 1)      // metric only if d_current is Measured
```

This is why `Measured<Double>` provenance matters: the same code path produces "step forward" or
"step forward 40 cm" depending on one input, with no separate branch.

### 6.4 Stability: deadband, hysteresis, smoothing (F-07)

Guidance that flickers is worse than no guidance.

- **Smoothing**: subject bounds and pose joints pass through a **One Euro filter** (low lag when
  moving, strong smoothing when still). A plain EMA trades one for the other and is not good enough
  for handheld framing.
- **Deadband**: no cue is emitted while error < `enterTolerance`.
- **Hysteresis**: once satisfied, a cue only reappears when error > `exitTolerance`, with
  `exitTolerance ≈ 1.6 × enterTolerance`. Prevents boundary oscillation.
- **Minimum dwell**: a cue must persist ≥ `minimumCueDuration` (≈250 ms) before it can be replaced,
  so cues do not strobe as the ranking changes.
- **Cue budget**: at most **one cue per actor**, at most **three total** on screen. Ranked by
  priority × normalized error. Humans cannot act on five simultaneous corrections.

### 6.5 The rigid-coupling rule (metric guidance validity)

ARKit gives a genuinely metric camera pose — but **for the iPhone**. In External Camera Mode with
the Sony on a tripod, the iPhone's pose describes the phone, not the camera, and photographer-
movement guidance derived from it is meaningless.

**Rule:** metric photographer guidance requires `FrameSource` and `MotionSource` to be *rigidly
coupled*, declared explicitly at composition time:

```swift
enum MotionCoupling { case rigid, decoupled, unknown }
```

- Phone Camera Mode → `.rigid`.
- External camera, phone hand-held → `.decoupled` → all photographer cues become `.relative`.
- External camera, phone mounted on the rig → `.rigid`, but only after the user confirms it.

`GuidanceEngine` refuses to emit `.metric` when coupling is not `.rigid`. Unit-tested.

`goal.md` also implicitly assumes "photographer" and "camera" move together. On a tripod they do
not, which is why `GuidanceActor` distinguishes them and why cues are addressed to an actor.

### 6.6 Plan trigger policy (F-04, N-04)

Re-plan **only** when at least one of these fires, subject to a hard rate limit and single in-flight
request (new requests coalesce, they do not queue):

| Trigger | Note |
|---|---|
| No plan latched | cold start |
| Plan age > `expiresAfterSeconds` (default 20 s) | staleness |
| Scene-change score > threshold | subject count changed, tracked subject moved > 15% of frame, scene luma shifted > 1 EV, camera moved > 0.5 m, focal length changed |
| User tapped "re-plan" | always allowed, resets the rate limiter |
| Capture completed | drives the review→retake loop (F-11) |

Scene-change scoring is a pure function of two `SceneState`s in `ForgeCore` — trivially unit-testable
and the main lever for controlling AI cost.

### 6.7 `HeuristicDirector` — one implementation, two jobs

A deterministic, offline `DirectorProvider` in `ForgeCore` implementing rule-of-thirds placement,
horizon leveling, headroom, and lead-room rules.

It is simultaneously:
- the **F-30 graceful-degradation path** (no backend, no key, no network), and
- the **test double** used by every guidance and replay test.

One implementation, no divergence between "what tests exercise" and "what users get offline". This
also means phase 2 delivers a genuinely useful app *before any AI exists*.

### 6.8 Exposure engine

Pure function `(SceneState, CompositionPlan.exposure, CameraCapabilities) -> ExposurePlan`. Applies
priority (subject / highlights / motion), reciprocal-rule minimum shutter from focal length, and
clamps every value to the camera's declared supported set. Emits `manualRequest: true` cues for
parameters the adapter cannot write (F-33). No camera I/O inside the engine — it returns a plan; the
`CameraController` decides whether to apply it based on the control level (F-23).

---

## 7. Repository Layout

Shallow, as required by `goal.md` §13. Four top-level directories.

```
Forge-Camera/
├── Package.swift                 # all cross-platform code, buildable headlessly
├── Makefile
├── project.yml                   # XcodeGen spec for the iOS app  [see §12 D-1]
├── README.md  goal.md  plan.md  ARCHITECTURE.md  CONTRIBUTING.md  AGENTS.md  LICENSE
├── Sources/
│   ├── ForgeCore/               Domain/  Guidance/  Exposure/  Director/  Policies/
│   ├── ForgeVision/
│   ├── ForgeCapture/
│   ├── ForgeDirector/
│   ├── ForgeBridge/
│   ├── ForgeCameraSony/
│   ├── ForgeDirectorCodex/
│   ├── ForgeTestSupport/
│   └── forge-server/            executable, macOS only
├── App/                          iOS app sources (SwiftUI) + Info.plist + assets
├── Tests/
│   ├── ForgeCoreTests/  ForgeVisionTests/  ForgeDirectorTests/  ForgeBridgeTests/
│   ├── ReplayTests/
│   └── HardwareTests/           gated, never run in CI
├── Fixtures/
│   ├── plans/                   valid + malformed CompositionPlan JSON
│   ├── scenes/                  synthetic SceneState JSON
│   ├── golden/                  expected GuidanceState sequences
│   └── sessions/                recorded .forgesession bundles (git-lfs)
└── Tools/                        scripts used by the Makefile
```

Nesting inside a module stops at two levels. If a third is needed, the module is probably two
modules.

---

## 8. Build, Tooling, and Headless Workflow (N-12)

### 8.1 Why most code lives in `Package.swift`

`swift build` / `swift test` need no `.xcodeproj`, no simulator, no code signing, and no GUI. Every
line that *can* live in the package *must*, so that the fast, headless, hardware-free loop covers as
much of the codebase as possible. The Xcode project contains only SwiftUI views, assets, entitlements,
and `Info.plist`.

```swift
// swift-tools-version: 6.0
platforms: [.iOS(.v18), .macOS(.v15)],
swiftLanguageModes: [.v6],
```

### 8.2 Makefile targets

Portable syntax only (GNU Make 3.81, see §2).

| Target | Does |
|---|---|
| `make bootstrap` | install dev tools (`xcodegen`, `swiftformat`, `swiftlint`, `xcbeautify`, `gh`), git-lfs |
| `make project` | regenerate `Forge.xcodeproj` from `project.yml` |
| `make build` | `swift build` — **no hardware, no signing, no simulator** (N-08) |
| `make test` | `swift test` — unit + replay, deterministic |
| `make app` | `xcodebuild` the iOS app for the simulator |
| `make device` | build, install, launch on a connected device via `devicectl` |
| `make server` | run `forge-server` locally |
| `make archive` | signed archive |
| `make testflight` | upload via `xcrun altool`/`notarytool` |
| `make test-hardware` | `FORGE_HARDWARE_TESTS=1 swift test --filter Hardware` |
| `make record` | capture a `.forgesession` from a device or the simulator |
| `make replay SESSION=…` | re-run a session through the pipeline, diff against golden |
| `make lint` `make format` | SwiftFormat + SwiftLint |
| `make check` | `format --lint` + `lint` + `build` + `test` — the pre-push gate |

`make build` and `make test` must stay hardware-free forever. That is the contributor promise from
`goal.md` §14 and it is worth defending in CI.

### 8.3 CI

GitHub Actions on `macos-latest`:

1. `make check` — the whole gate.
2. `make app` — simulator build proves the app target still links.
3. **Boundary guard**: grep for vendor identifiers outside their owning modules (N-07) and for
   `import` statements violating §4.3. A ~20-line script in `Tools/check-boundaries.sh`. This is the
   difference between "we agreed on layering" and "layering is enforced".
4. **Secret guard**: `gitleaks` or equivalent (N-10).

CI never touches a camera, an API key, or a paid endpoint.

---

## 9. Testing Strategy

Swift Testing (`@Test` / `@Suite`), which ships with Xcode 16. Hardware gating uses
`.enabled(if: ProcessInfo.processInfo.environment["FORGE_HARDWARE_TESTS"] == "1")` so hardware tests
are *skipped*, not *absent*, and stay compiled.

| Tier | Covers | Runs in CI |
|---|---|---|
| **Unit** | `GuidanceEngine`, `ExposureEngine`, plan validation (valid + every malformed fixture), scene-change scoring, capability handling, coordinate round-trips, `HeuristicDirector` | ✅ |
| **Integration** | frame→`SceneState`, `SceneState`→plan (mock provider), plan→guidance, `CameraController`→`MockCameraAdapter` | ✅ |
| **Replay** | full pipeline over recorded sessions, golden-file diff (N-09) | ✅ |
| **Hardware** | real A7C II: connect, live view, read state, write setting, shutter, retrieve | ❌ manual |
| **Property** | invariants: normalized values stay in range; no `.metric` cue without `.rigid` coupling; cue count ≤ 3; hysteresis never oscillates on a monotone input | ✅ |

### 9.1 Session recording format

```
Fixtures/sessions/portrait-backlit-01.forgesession/
├── manifest.json        device, camera, lens, focal length, coupling, schema version
├── frames.jsonl         { index, timestamp, file, orientation }
├── frames/0000.jpg …
├── motion.jsonl         optional: gravity, ARKit pose per timestamp
├── director.jsonl       recorded plan requests + responses (replay without an AI)
└── golden.json          expected GuidanceState sequence
```

Replay feeds frames at recorded timestamps through the real pipeline with recorded director
responses, and diffs the resulting `GuidanceState` sequence against `golden.json`. Because
`GuidanceState` is `Equatable` and `Codable` and every engine is a pure function, this is exactly
reproducible (N-09) — which makes it the primary regression net for tuning §6.4's constants.

Sessions are binary and grow; store under **git-lfs** from the first commit. Retrofitting lfs is
painful.

---

## 10. Phases

Each phase ends with a demoable artifact and hard exit criteria. No phase starts before the previous
one's criteria are green.

### Phase 0 — Skeleton (no product behavior)
Repo, LICENSE (**[DECISION]** Apache-2.0 — the patent grant matters more than MIT's brevity for a
project that may touch vendor protocols), `Package.swift` with all targets stubbed, Makefile, CI,
SwiftFormat/SwiftLint config, `AGENTS.md`, boundary + secret guards, git-lfs.
**Exit:** `make check` green on a clean clone. N-08, N-12.

### Phase 1 — Domain + Guidance, headless (highest value, zero hardware)
`ForgeCore` in full: all types from §5, `GuidanceEngine` with §6.1–6.4, `ExposureEngine`,
`PlanTrigger`, `HeuristicDirector`, plan schema + validation, `ForgeTestSupport`, fixtures.
**Exit:** F-06 + F-05 done; unit and property tests green; `GuidanceState` computable from a
hand-written `SceneState` JSON with no device involved. *This phase is fully doable over SSH with no
camera, which makes it the right place to spend the most care.*

### Phase 2 — Phone Camera Mode, end to end, no AI
`ForgeCapture` + `ForgeVision` + SwiftUI overlay, driven by `HeuristicDirector`.
**Exit:** F-01, F-02, F-03, F-07, F-08, F-20, F-30, F-31 verified on device; N-01, N-02 measured and
recorded; first `.forgesession` recorded and replaying green.
**This is the first genuinely useful build** — a working composition assistant with zero AI cost.

### Phase 3 — Real AI Director
`ForgeBridge` wire protocol, `ForgeDirector` HTTP client (timeouts, retry, budget guard, in-flight
coalescing), `forge-server` on macOS, `ForgeDirectorCodex`, BYOK Keychain storage, settings UI for
backend selection.
**Exit:** F-04, F-05 against a real model; N-03, N-04, N-05, N-10 verified; killing the server
degrades cleanly to `HeuristicDirector` (F-30) with a visible indicator.

### Phase 4 — Capture and Review
Still capture, full-quality retrieval, `ReviewRequest`/`ReviewResult`, retake plan generation, review UI.
**Exit:** F-09, F-10, F-11 — the loop from `goal.md` §8 closes on the phone alone.

### Phase 5 — External Camera Mode
Camera bridge protocol (axis A, §4.1), `CameraCapabilities` model, `MockCameraAdapter` first,
`ForgeCameraSony` second, discovery + pairing UI.
**Exit:** the exact `goal.md` §20 checklist — connect, live view, read state, read focal length, set
≥1 exposure parameter, trigger shutter, retrieve preview (F-21, F-22, F-34); `MockCameraAdapter`
passes the identical adapter conformance test suite.

### Phase 6 — Camera Automation
`CameraController`, the three control levels with Ask-Before-Apply default, transactional apply,
manual-request cues.
**Exit:** F-23, F-24, F-33.

### Phase 7 — Computational Photography
Bracketing first (simplest, most useful), then focus stacking, then the rest — each an independent
module behind a capability check, recommended by the Director.
**Exit:** F-25 for at least bracketing, with the Director able to recommend it (`goal.md` §7).

---

## 11. Engineering Guidelines

Binding on humans and on coding agents. `AGENTS.md` will restate the machine-checkable subset.

### Code
- **Readable over clever.** If a reviewer needs the author to explain it, rewrite it.
- **Small public surface.** Default to `internal`; `public` is a deliberate act. Every `public` symbol
  in `ForgeCore` needs a doc comment.
- **Domain names.** `CompositionPlan`, `GuidanceState`, `ExposurePlan`, `CameraCapabilities`. Banned
  suffixes: `Manager`, `Helper`, `Utils`, `Processor`, `Handler`, `Service`, `Thing` — unless the
  word is genuinely the role (`URLSessionDirectorTransport` is fine; `AIManager` is not).
- **Value types by default.** Reference types only for identity or resource ownership.
- **Pure engines.** `GuidanceEngine`, `ExposureEngine`, `PlanTrigger`, validation: no I/O, no clock,
  no randomness, no logging side effects. Time and randomness are injected. This is what makes N-09
  possible.
- **Initializer injection only.** No singletons, no service locator, no DI framework (`goal.md` §13).
- **No premature abstraction.** Second concrete implementation, or a documented near-term
  requirement, before a protocol. The five protocols in §4.4 are the budget; adding a sixth needs a
  paragraph of justification in the PR.
- **Named constants.** Every threshold lives in a `*Policy` struct (§6).

### Concurrency (N-11)
- Swift 6 language mode, strict concurrency, warnings as errors in CI.
- Domain types are `Sendable` value types. Stateful pipeline components are `actor`s.
- Frame delivery on a dedicated serial queue; **never** the main actor. UI updates hop to
  `@MainActor` at the view-model boundary only.
- **Back-pressure by dropping.** Frame buffers hold 1, latest wins. Never queue frames — a queued
  frame is stale guidance.
- `CVPixelBuffer` never escapes the analyzer. Extract what is needed and release.
- `@unchecked Sendable` requires a comment explaining the invariant that makes it safe.

### Errors
- Typed errors per module (`DirectorError`, `CameraError`, `CaptureError`). No `NSError` bridging in
  domain code, no stringly-typed failures.
- Errors that a user can act on carry a user-facing recovery suggestion; errors that they cannot are
  logged and degraded around (F-35).
- Never `try!`, never `fatalError` outside genuine programmer errors in `init`.

### Logging and privacy (N-10)
- `OSLog` with one subsystem, one category per module.
- **Default `privacy: .private`.** `.public` is opt-in and must be provably non-sensitive.
- Never log: API keys, image data, file paths containing user content, precise location.
- Secrets in Keychain, read at point of use, never held in a long-lived property, never in
  `UserDefaults` or a plist.
- Images sent to a Director are downscaled (longest edge ≈1024 px), re-encoded, and **stripped of
  EXIF and GPS**. A "structured state only, no images" mode must exist and be honored end to end.
- `Info.plist` needs `NSCameraUsageDescription`, `NSPhotoLibraryAddUsageDescription`,
  `NSLocalNetworkUsageDescription`, and `NSBonjourServices` for the Mac bridge.

### Git and PRs
- Conventional commits; imperative subject; body explains *why*.
- One concern per PR. A PR that touches both `ForgeVision` and `ForgeCameraSony` is probably two PRs.
- **Definition of done:** `make check` green · tests for new behavior · no new public API without doc
  comments · no new dependency without a justification paragraph · `ARCHITECTURE.md` updated if the
  module graph changed · requirement IDs referenced in the description.

### Dependencies
Apple frameworks first. A third-party dependency needs: what it solves, why the platform cannot,
license compatibility, maintenance status, and the cost of removing it later. Expected count in the
iOS app: **zero**. Dev-time tools (XcodeGen, SwiftFormat, SwiftLint) are not app dependencies and
are held to a lower bar.

---

## 12. Open Decisions, Verifications, and Risks

### Decisions to confirm before phase 0 closes

| ID | Decision | Recommendation |
|---|---|---|
| D-1 | Xcode project generation | **XcodeGen** (`project.yml`). Fully reproducible from text, no `.pbxproj` merge conflicts, headless-friendly. Alternative: a thin hand-made project using Xcode 16 synchronized folders. Low stakes either way — ~95% of the code is in SwiftPM. |
| D-2 | License | Apache-2.0 |
| D-3 | Deployment targets | iOS 18 / macOS 15 (§2) |
| D-4 | Camera bridge transport | HTTP + multipart over Bonjour-discovered local network, MJPEG for live view first (simple, debuggable with `curl`), WebRTC only if latency proves unacceptable |

### Verifications — do these before designing around them

| ID | Claim to verify | Why it matters |
|---|---|---|
| V-1 | Sony Camera Remote SDK has **no iOS build**, supports macOS arm64, and lists ILCE-7CM2 as supported | Determines whether the Mac bridge is mandatory (§4.1). Check Sony's current support matrix. |
| V-2 | CrSDK's license permits redistribution in an open-source repo | If not, ship the *adapter* and have `make bootstrap` fetch the SDK; never vendor it |
| V-3 | A7C II USB streaming (UVC) resolution/frame-rate, and whether it can coexist with PC Remote control on the same connection | A UVC live view + PTP control split may be simpler than CrSDK live view |
| V-4 | `libgphoto2` coverage for the A7C II (LGPL-2.1, dynamic linking only) | A viable, fully open alternative path — `libusb` is already installed |
| V-5 | Whether iPhone (not just iPad) supports `AVCaptureDevice.DeviceType.external` on iOS 18 | If yes, a direct USB-C live-view path exists with no Mac; if no, §4.1's bridge is unavoidable |
| V-6 | `codex exec` non-interactive JSON output stability and latency | Determines whether Codex is viable as a phase-3 backend or only a prototype |
| V-7 | On-device Vision body-pose throughput at the target resolution | Validates N-01 before the phase-2 architecture is locked |

### Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Vendor SDK licensing blocks distribution | External camera mode unshippable as OSS | V-2 early; adapter-not-SDK in-repo; keep `libgphoto2` as plan B (V-4) |
| Guidance feels jittery or naggy | Product fails its core promise | §6.4 is a first-class feature, not polish; tune against recorded sessions with golden-file diffs |
| AI latency/cost makes the loop unusable | Directors get bypassed | §6.6 trigger policy + `HeuristicDirector` doing the real-time work; AI is advisory and latched |
| Metric guidance that is quietly wrong | Users lose trust permanently | §5.4 makes it a type error; §6.5 makes coupling explicit |
| Abstraction creep | The exact failure `goal.md` §23 warns about | Five protocols (§4.4) as a hard budget; boundary guard in CI |
| iOS/macOS split doubles the work | Slower delivery | Phases 1–4 are phone-only and deliver a complete product; phase 5 is additive |

---

## 13. What Ships First

If only one thing gets built: **phases 1 and 2**. A phone app that watches a scene, applies
deterministic composition rules, and gives stable, honest, non-flickering guidance — with no AI, no
account, no network, and no external camera — is already useful, is fully testable headlessly, and
is the substrate every later phase plugs into. Everything after it is a swap of one protocol
implementation for a better one.
