# Handoff

Continuity between coding sessions and between agents (Codex ↔ Claude Code).
**Read this before starting work. Update it before finishing.**

Scope: current state, work in flight, decisions already made, and knowledge that is not
recoverable from the code. It deliberately does **not** restate `goal.md` (why the
project exists), `plan.md` (phases and requirements), the skills in `.agents/skills/`
(how to build things), or `git log` (what changed). If a fact lives in one of those,
link to it instead of copying it.

---

## Current state

**Last updated:** 2026-08-20 · **Phase:** 1 complete, 2 vertical slice closed; loopback real-AI server passes

| | |
|---|---|
| Tests | 182, all passing |
| `make check` | Passing (format, lint, build, test, skills, boundaries) |
| CI | The Swift 6.1 and boundaries fixes are pushed on `origin/main`; the remote run after the latest commit has not been checked in this session. |
| Device status | The user confirmed the clean live-camera baseline and deterministic single target frame on an iPhone: preview runs, the frame and outside scrim render correctly in portrait, and the rejected two-box UI, slider harness, and synthetic Compose screen are absent. Landscape still needs a direct visual check. Quantitative N-01/N-02 measurements and broad device coverage remain undone. |

### Built and verified

`ForgeCore` (Foundation only) —

- **Domain**: `NormalizedPoint`/`NormalizedRect` (top-left origin, y down), `Angle`,
  `FieldOfView`, `Measured<T>` with provenance, `SceneState` and detection types.
- **Director**: `CompositionPlan` + `PlanValidator` (field-level degradation), including additive
  schema-v1 subject/theme selection, source region, visual anchor, target photograph frame, and
  display-only advice; `DirectorProvider`, `HeuristicDirector`, `PlanTrigger`.
- **Guidance**: `GuidanceState`, `GuidanceEngine` (+`GuidanceEngine+Cues`),
  `GuidanceCueFormatter`.
- **Exposure**: `ExposureCapabilities`, `ExposureEngine`.
- **Policies**: `GuidancePolicy`, `ExposurePolicy`, `PlanTriggerPolicy`.
- **Frame contracts**: generic `SceneFrame`, `FrameSource`, and `SceneAnalyzer`; platform image
  types do not enter the domain.

`ForgeTestSupport` — `SceneFixtures`, `PlanFixtures`, `MockDirectorProvider`,
approximate-equality helpers, and deterministic `RecordedFrameSource` replay with explicit
advancement and newest-one buffering.

`ForgeFrame` — the narrow shared CoreVideo ownership boundary. `PixelBufferFrame` owns an
independent, read-only copy and package-scoped intrinsics; future `ForgeVision` can consume it
without depending on `ForgeCapture`.

`ForgeVision` — on-device perception. `VisionSceneAnalyzer` batches human-rectangle and
body-pose requests through one `ImageRequestHandler`, converts all Vision geometry into Forge
normalized space at the boundary, drops low-confidence joints, and matches each pose to a person by
joint centroid. `SubjectTracker` assigns identities by nearest-centre matching with a gate, but its
declared missing-frame tolerance does not retain bounds in the returned scene; a one-frame miss still
removes the visible subject and can break identity recovery. Treat tracking stability as unfinished.

`ForgeDirectorCodex` — development-Mac image-to-plan proof. `CodexDirectorSpike` accepts one JPEG or
PNG, re-encodes decoded pixels to a metadata-free JPEG with a 1024-pixel maximum edge, stages only
generic temporary filenames, and invokes the installed CLI with `--ephemeral`, `--ignore-user-config`,
read-only sandboxing, and a strict output schema. It decodes into `CompositionPlan`, verifies the
request identity, and applies `PlanValidator`. The CLI owns existing authentication; the module does
not read or copy credentials. The command is explicit: `make codex-spike IMAGE=/path/to/image.jpg`.

`ForgeBridge` + `forge-server` — the first development HTTP boundary around that provider.
`GET /health` is local-only and never invokes planning. Multipart `POST /v1/plan` accepts one field
named `image`, bounds headers and body size, permits JPEG/PNG only, stages a generic temporary file,
and returns root `CompositionPlan` JSON or a stable redacted error. The executable is a narrow
composition root that injects `CodexDirectorSpike`; bridge code has no Codex dependency. The server
hard-binds IPv4 `127.0.0.1:8765`, handles one request at a time, and logs neither request images nor
credentials. `make server`, health `curl`, and a real HTTP image-to-plan request all pass.

`CapturePipeline` (in `ForgeCore`) — the spine. Frames in, guidance out, with the three rates kept
separate: analysis per frame, planning on the trigger policy, guidance recomputed every frame from
the latched plan. It applies `isCurrent` before analysis, so the stale-frame obligation is
discharged. Free of randomness, hence replay-deterministic.

`ForgeCapture` — initial AVFoundation source: permission and lifecycle status, a serial session
queue, back-camera 1080p/NV12 configuration, RotationCoordinator, camera intrinsics delivery,
newest-one frame streaming, bounded buffer-copy pool, and typed actionable errors. Synthetic
sample-buffer tests verify ownership, metadata, drop accounting, and back-pressure without hardware.
Permission is now behind the `CameraAuthorization` seam, so the lifecycle races that matter —
concurrent starts, task cancellation, stopping mid-prompt, backgrounding mid-prompt — are pinned by
hardware-free tests. `PreviewGeometry` maps Forge normalized image geometry into an aspect-fill
viewport using the orientation-corrected frame dimensions and an explicit preview-mirroring flag;
asymmetric tests cover crop offsets, portrait rotation, mirroring, and invalid sizes.

`App` — `CaptureScreen` is now the entry point, backed by `CaptureModel`, the composition root that
wires `AVFoundationFrameSource` + `VisionSceneAnalyzer` + `HeuristicDirector` into `CapturePipeline`.
`CameraPreviewView` hosts an `AVCaptureVideoPreviewLayer` fed by the session **directly**, never by
the frame stream, so a slow analysis pass cannot stall the viewfinder. The app is deliberately back
to a clean live-camera baseline: camera preview, compact status, typed cues, and future-safe
horizon/avoid-region overlay only. There is no Compose button, synthetic gray composition screen,
stage picker, or slider harness. Raw current/target subject rectangles were removed from
`OverlayModel` and `GuidanceEngine`, not merely hidden. The real preview now renders one large,
deterministic target frame with a restrained outside scrim to validate the production presentation
and coordinate path. `visualAnchor`, `targetFrame`, and display-only advice remain the new
Director-to-presentation contract; the deterministic frame is not AI-selected yet.
The HUD does not present `GuidanceState.Readiness.ready` as a user-facing “Ready” badge: until a
valid composition plan is active, that state only means there is no correction cue, not that the
photograph is ready to take.

Verified in the simulator, end to end: the permission prompt appears with the real purpose string
and the HUD shows `awaitingPermission`; granting it then advances to session configuration, fails
with `cameraUnavailable` because a simulator has no camera, and the app shows that error's recovery
suggestion without substituting a fake camera scene.

An earlier physical-iPhone run exposed the product and implementation gaps recorded in D-5–D-7:
human-only perception, raw two-box guidance, per-frame flicker, oversized target geometry, and an
aspect-fill mapping error. The user has since verified the corrected clean baseline on the same
device: live preview works and the rejected rectangles and synthetic Compose UI are absent.

### Not built yet

No session recorder. Basic device operation is now observed, but Vision throughput, tracking quality,
preview/guidance alignment, latency, and every performance budget (N-01, N-02) remain unmeasured.
F-01/F-02 are qualitatively proven on one device; F-03 is not satisfied because dropout stability is
not working as intended.

Most of Phase 3 onward remains unbuilt: LAN/pairing and app-side network Director, phone
planning-image delivery, capture and review loop, and all external-camera work. Horizon, lighting, and device motion are still `nil` in
`SceneState` — `VisionSceneAnalyzer` reports subjects only, so levelling and exposure guidance have
no input yet. CoreMotion gravity is the cheap next win there.

The D-12 Mac-only proof is implemented and passed two real requests. Both cat images produced animal
selections, usable anchors/frames, and three display suggestions with clean validation. Latencies
were 13.28 and 10.19 seconds. V-6 remains partial because person, object, and scene-level inputs and
a latency distribution have not been measured.

The newly confirmed Phase 3 product interaction is still mostly unbuilt. Its core plan contract,
presentation state, development Codex provider, and loopback HTTP server exist, but the discarded
synthetic interaction preview is gone. Live-camera planning-image delivery, an app-side network
`DirectorProvider`, LAN pairing/discovery, user override, local arbitrary-region
tracking, automatic anchor-to-frame transition, AI-driven live-preview rendering, photo capture,
and actual still-image cropping do not.

---

## In flight

**Uncommitted work contains the additive composition contract plus the clean-baseline correction:**
`CaptureScreen`, `CaptureModel`, `GuidanceOverlayView`, removal of `GuidancePreviewScreen`,
`PreviewGeometry` and its tests, guidance presentation state/mapping and its core test, the new
`ForgeDirectorCodex` spike/module/tests, `ForgeBridge`, `forge-server`, their endpoint tests,
`plan.md`, `README.md`, the UI guidance skill reference, and this handoff. The contract slice is committed and pushed as
`070177a`; later UI work is not committed.

**The checked-out `Forge.xcodeproj` is regenerated for the deletions.** Its PBX file contains no
references to `GuidancePreviewScreen` or `AIComposeOverlayView`; local package resolution and the
formal project build both pass. Xcode was open during regeneration, so its current window may still
hold the old in-memory project. Quit Xcode and reopen `Forge.xcodeproj` before the next phone run.

The prior Swift portability/CI fixes are committed and pushed as `cd9db89` and `45de3bb`.

**Next task, in order:**

1. ~~Record the physical-device product decision before changing code.~~ **Done** — see `plan.md`
   D-5–D-7 and the updated Director/UI skill references.
2. ~~Make the contract change first: structured selection, anchor, frame, advice, validation,
   fixtures, and boundary guards.~~ **Done** as additive schema version 1; 164 tests pass.
3. ~~Carry anchor, frame, and advice into presentation state.~~ **Done.**
4. ~~Remove rejected UI paths.~~ **Done** — no raw double-box state, sliders, gray Compose harness,
   or fake-scene fallback remains in the app.
5. ~~Render one deterministic target frame over the real camera preview using a tested
   aspect-fill/rotation/mirroring conversion.~~ **Implemented and accepted on a physical iPhone in
   portrait.** No AI, crop, or capture was added; landscape remains a verification item.
6. ~~Choose the first real Director backend.~~ **Done** — D-12 selects a trusted development Mac
   running its installed, already-authenticated Codex CLI. This does not make Codex CLI a permanent
   production backend.
7. ~~Build a Mac-only V-6 spike.~~ **Done** — two real animal-scene requests returned usable structured
   guidance and passed validation in 13.28 and 10.19 seconds. The module sanitizes images internally
   and has eight offline tests. V-6 subject coverage and latency distribution remain partial.
8. ~~Wrap the provider in a minimal loopback-only `forge-server`.~~ **Done** — `GET /health` and
   multipart `POST /v1/plan` pass endpoint tests and a real localhost `curl`; `make check` passes
   with 182 tests. The listener is deliberately restricted to `127.0.0.1`.
9. Add a development per-session pairing token, explicitly enable a LAN listener, and implement the
   iPhone HTTP `DirectorProvider` plus privacy-sanitized selected-frame delivery. Preserve
   structured-state-only degradation; do not expose arbitrary prompts or shell execution.
10. Initialize local arbitrary-region tracking from the AI selection and support tap-to-replace.
11. Replace the deterministic frame source with the selected AI plan and automatic
   visual-anchor-to-target-frame transition.
12. Add still capture, then implement the selected crop against captured pixels with review/undo.
13. Record and replay real sessions, then measure N-01/N-02 and tune stability. CoreMotion horizon and
   frame-statistics lighting follow once the new core composition loop is trustworthy.

The stale-buffered-frame limitation is **resolved and discharged**: `CapturePipeline.run()` applies
`source.isCurrent(frame)` before analysis and counts rejections in `framesDroppedAsStale`.

Known and accepted: concurrent `start()` calls each query permission rather than sharing one
request. AVFoundation coalesces the visible prompt, so this is invisible to the user, and
deduplicating it would add machinery for no observable gain. `CaptureLifecycleTests` pins the
property that matters — all callers resolve and agree — rather than the call count.

---

## Blockers

**~~No local iOS platform/runtime.~~ Resolved** by `xcodebuild -downloadPlatform iOS`. The iOS 18.0
runtime and simulators are installed, `make app` exits 0 locally, and the app has been booted,
installed, and screenshotted in the iPhone 16 Pro simulator. Local app builds are now trustworthy.

**The local compiler is still older than CI's.** Local Xcode 16.0 is Swift 6.0; CI selects Xcode
16.4, which is Swift 6.1. With `-warnings-as-errors` that makes CI strictly stricter than `make
check` — see the Traps entry. Installing Xcode 16.4 locally would close it.

The workaround is now a script rather than an incantation to retype:

```sh
make ios-typecheck        # or ./Tools/typecheck-ios.sh
```

It compiles each package boundary in dependency order and type-checks `App/` against them, with the
device SDK, Swift 6, complete strict concurrency, and warnings as errors. It does **not** link or
produce a bundle, so it proves the code compiles, never that the app runs. Verified to fail on a
planted error in both a package target and the app.

**Physical-device signing is not durable across project regeneration yet.** The user previously
installed the app from Xcode, but `xcodegen` rewrites the generated project from `project.yml`.
When `FORGE_DEVELOPMENT_TEAM` is absent, a signed device build fails with "requires a development
team" even though unsigned device compilation and simulator builds pass. Set the environment value
before `make project`/`make device`, or reselect the Personal Team after each regeneration. The
current project contains Team `5UGBG76CPV` and a valid matching keychain identity, but Xcode reports
that no Apple Account for that team is signed in; add or reauthenticate that account in Xcode before
automatic provisioning can create the profile.

---

## Decisions already made

Do not re-litigate these without a reason. Rationale is recorded so the reasoning
survives, not just the conclusion.

| ID | Decision | Why |
|---|---|---|
| D-1 | **XcodeGen** generates `Forge.xcodeproj` from `project.yml` | Reproducible from text, no `.pbxproj` merge conflicts, headless-friendly. The project is gitignored — it is a build artifact. Regenerate with `make project`. |
| D-2 | **Apache-2.0** over MIT | Express patent grant, which matters for computational photography and camera control. Swift ecosystem norm. |
| D-3 | **iOS 18 / macOS 15**, Swift 6 language mode | Unlocks the modern Vision Swift API, which is async/Sendable-native and avoids wrapping completion-handler `VNRequest` code under strict concurrency. |
| D-4 | Camera bridge: HTTP + MJPEG over Bonjour first | Debuggable with `curl`, no dependencies. Revisit only if measurement shows latency is the bottleneck. |
| D-5 | The Director proposes the photographic subject or scene theme from a selected planning image; it is not limited to human detections | A valid subject can be a person, animal, object, place, scene, light, or relationship. AI chooses at planning cadence; local perception tracks at frame cadence. See `plan.md` §5.3. |
| D-6 | Production guidance uses visual-anchor acquisition followed by one target photograph frame; current/target detection rectangles do not enter `OverlayModel` | Detection bounds explain the detector, not the intended photograph. Developer diagnostics must inspect perception state separately. |
| D-7 | Short AI shot advice is display-only | It may explain the plan in a compact popup, but structured geometry and typed cues are the only control state. |
| D-8 | Subject selection, target framing, and display advice are additive optional fields in `CompositionPlan` schema version 1 | Existing v1 plans decode unchanged; no version bump is needed for optional data older clients already ignore. Unknown subject kinds remain round-trip safe. |
| D-9 | One target frame is the only user-facing framing geometry; no coordinate sliders. Move the camera to match it, or tap it to select post-capture auto-crop | The crop choice must remain explicit and be applied to captured still pixels. Never present a preview transform as a completed crop. |
| D-10 | Do not expose core `Readiness.ready` as a shot-ready HUD badge until a valid composition plan and measurable target constraints are active | With no actionable plan, `.ready` can mean only “no correction cue”; presenting it as “Ready” fabricates confidence in the composition. |
| D-11 | Every image-space overlay maps through tested aspect-fill geometry using orientation-corrected frame dimensions and explicit preview mirroring | Multiplying normalized coordinates by view size is wrong whenever `.resizeAspectFill` crops the camera image, and independently reapplying rotation causes a second transform. |
| D-12 | The first real-AI validation runs on a trusted development Mac through its installed, already-authenticated Codex CLI; first prove a Mac-only image-to-`CompositionPlan` spike, then place it behind `forge-server` for iPhone access | This minimizes prototype work and keeps OpenAI credentials off the phone and out of the repository. BYOK, user accounts, backend-selection UI, and production credential provisioning are deferred. The provider boundary remains replaceable. |
| D-13 | An unauthenticated development planning endpoint may bind only to `127.0.0.1`; any LAN listener requires a per-session pairing token first | The loopback slice can stay minimal without allowing another local-network device to spend the Mac user's Codex account or submit arbitrary images. |
| — | Canonical skills in `.agents/skills/`, **no `.codex/skills/`** | Codex scans `.agents/skills` and `.codex/skills` as separate roots and does **not** deduplicate — a skill reachable from both is listed twice. Verified against Codex 0.144.6. |
| — | gitleaks **CLI** in CI, not `gitleaks-action` | The action needs a licence key for org-owned repos (free for one repo, paid beyond). The CLI is MIT with no key. Version and SHA-256 both pinned. |
| — | `GuidanceCueFormatter` lives in `ForgeCore`, not the app | Pure, no UI dependency, and it is the single point where "never fabricate precision" becomes visible text. In the package, `swift test` covers it everywhere. |
| — | `SceneFrame<Content>` is generic; `ForgeFrame` owns the CoreVideo wrapper | Keeps `ForgeCore` Foundation-only and avoids a forbidden sibling dependency between capture and Vision. `ForgeCapture` copies borrowed AVFoundation storage into this neutral package-internal boundary. |
| — | XcodeGen is fixed at **2.46.0** | Generated project output is tool-version-dependent. The Makefile checks the version and CI installs the release archive by pinned SHA-256 instead of tracking Homebrew latest. |

Open decisions are tracked in `plan.md` §12 along with the verification list (V-1…V-7).

---

## Traps

Things that cost time once. Each is now guarded by a test, a comment, or a CI check —
but they are the sort of thing that gets reintroduced.

**`RawRepresentable` derives `==` from `rawValue`.** For the forward-compatible enums
(`PhotographicIntent`, `ExposurePriority`, `CaptureKind`, `PoseHint`),
`.depth == .unknown("depth")` is **true**. A check like `value != .unknown(value.rawValue)`
is therefore always false and silently does nothing — this shipped as a real bug where
every explicit exposure priority was discarded and re-inferred. Detect an unrecognised
case with the `isKnown` pattern match. Pinned by a regression test in
`ExposureEngineTests`.

**Exact float equality on derived geometry fails.** `0.2 + 0.4 == 0.6000000000000001`,
and flipping a rect twice returns `0.20000000000000007`. Use
`isApproximately(_:)` from `ForgeTestSupport` for *derived* values; keep exact
comparison for copied and discrete ones.

**Symmetric test fixtures hide flip bugs.** A centred square passes a broken vertical
flip. Geometry fixtures are deliberately off-centre and non-square.

**Substring checks on user-facing text give false positives.** `"Move left"` contains
`"ft"`. Compare word by word.

**`printf("%.1f")` rounds half to even**, so `1.25` renders as `1.2`. Avoid values
ending in 5 in formatting tests unless rounding is the thing under test.

**SwiftFormat and SwiftLint can contradict each other.** `--commas always` versus the
`trailing_comma` rule was a hard conflict. SwiftFormat is the tool that writes;
SwiftLint yields. If `make check` and CI ever disagree, suspect this class of problem
first — and note that `make lint` deliberately uses `--strict` to match CI exactly.

**A guard that never fires is worthless.** `Tools/check-boundaries.sh` was written with
a regex that missed `rationale?.contains(...)` because it did not allow optional
chaining. Plant a deliberate violation and confirm the guard catches it before trusting
it. The import scanner later failed silently on modifier imports and missed semicolon/block-comment
forms; `Fixtures/boundaries/import-syntax.swift` is now a permanent self-test.

**Borrowed camera buffers are not Sendable storage.** AVFoundation owns and reuses the
`CMSampleBuffer`/`CVPixelBuffer` after its delegate returns, and `CVPixelBuffer` is explicitly
non-Sendable in Swift 6. Copy into the bounded `ForgeFrame.PixelBufferFrame` pool before yielding;
never weaken the compiler with a raw-buffer conformance. Camera intrinsics are a sample-buffer
attachment and must be copied separately.

**Measure exit codes, not `tail`'s.** `cmd | tail -1; echo $?` reports the exit status of
`tail`. This produced two wrong "it passes" conclusions in one session.

**zsh does not word-split unquoted variables.** `COMMON="-sdk … -target …"; swiftc $COMMON` passes
the whole string as one argument and swiftc rejects it — while a `grep error:` pipeline happily
printed "ok" for every module. Shared compiler flags belong in an array (`"${COMMON[@]}"`), which is
why `Tools/typecheck-ios.sh` is `#!/bin/bash` with an array rather than an inline command.

**`swift test` and `make test` are not the same gate.** `make test` adds
`-Xswiftc -warnings-as-errors`, so a redundant `try?` passes one and fails the other. Run `make
check` before believing the work is finished.

**CI compiles with a newer Swift than the local machine, and warnings are errors.** CI selects
Xcode 16.4 (Swift 6.1); the local install is Xcode 16.0 (Swift 6.0). A diagnostic added in 6.1 is a
hard CI failure that `make check` cannot see. The instance that cost a red build: reducing a
platform-specific value to a `false` constant in an `#else` branch made the following condition
provably unreachable, which 6.1 reports as dead code. Compile a platform-specific path only under
its own `#if` rather than neutralising it with a constant. **Installing Xcode 16.4 locally closes
this gap and the missing-iOS-platform blocker at once.**

**Vision defines its own `NormalizedPoint` and `NormalizedRect`.** Same spelling as the domain
types, different convention (bottom-left origin), different module. Inside `ForgeVision` an
unqualified reference is a compile error, not a silent mix-up — but qualify with `ForgeCore.` and
`Vision.` anyway so a reader knows which is meant. All conversion lives in `VisionGeometry.swift`.

**A new test target is invisible until `.build` is cleared.** Adding `ForgeVisionTests` to
`Package.swift` left `swift test` reporting the *old* count as passing — the new suite never ran and
nothing said so. Tests that appear to pass while not running is the worst possible failure mode. If
a test count does not rise after adding a target, `rm -rf .build` before believing it.

**The two Swift versions disagree in opposite directions.** `withExtendedLifetime(x) { #expect(throws:) {…} }`
returns Void under 6.0 but not under 6.1, so `_ =` is "redundant" to one compiler and required by the
other — no single spelling satisfies both. The fix was to restructure so there is no result to argue
about. Expect more of these while local and CI compilers differ; a construct that needs `_ =` is a
warning sign.

**SwiftFormat can undo a portability fix.** An explicit `-> Void` closure annotation added precisely
to pin the return type was stripped by the formatter on the next run, silently reverting the fix.
If a fix depends on syntax the formatter owns, restructure instead of annotating.

**Live planning is a race by design, so replay needs `.synchronous`.** `CapturePipeline` runs the
director detached so a slow reply cannot stall the frame loop, which means the plan lands on
whichever frame follows it. A determinism test against the default mode failed roughly one run in
eight. `PlanningMode.synchronous` exists for replay and regression work (N-09); live capture keeps
`.concurrent`. Any future golden-file replay must use it.

**A single-slot continuation deadlocks multiple waiters.** A test double holding one
`CheckedContinuation` silently dropped all but the last concurrent caller, and the suite hung
instead of failing. Test doubles for concurrent code need a waiter list.

**Aspect-fill preview coordinates are not SwiftUI view coordinates.** `CameraPreviewView` uses
`.resizeAspectFill`, while the current `GuidanceOverlayView` multiplies Forge-normalized coordinates
by the full SwiftUI size. That is wrong whenever the preview is cropped and was visible on device as
misaligned/oversized guidance. The new anchor and target-frame overlay must convert through the
preview layer (or an explicitly tested visible-rect transform), including rotation and mirroring.

**The current missing-frame tolerance does not stabilize output.** `SubjectTracker` increments a
missing counter but returns only detections from the current frame. On the first Vision miss the
subject disappears from `SceneState`; on the next frame the previous scene is empty, so the old
identity cannot be matched. Do not tune the tolerance constant and assume flicker is fixed — the
tracking state model itself must retain the last observation with an explicit stale/confidence rule.

**Codex structured-output object schemas require every declared property to appear in `required`.**
Model-optional fields must still be required and use a nullable schema. The first live spike failed
with `invalid_json_schema` because `selection.sourceRegion` was declared but omitted from `required`;
it is now required as rectangle-or-null, and an offline recursive schema test guards this rule.

**Signing selected only in the generated Xcode project is temporary.** `make app`, `make project`,
and `make device` regenerate `Forge.xcodeproj`; an Xcode-only Personal Team selection is overwritten.
Set `FORGE_DEVELOPMENT_TEAM` before generation if physical-device builds must remain repeatable.

**An open Xcode window can retain the package graph from before project regeneration.** The generated
project correctly references local products `ForgeCore`, `ForgeCapture`, and `ForgeVision`, but
running `make app`/`make project` while Xcode has `Forge.xcodeproj` open may make the window report
"Missing package product ForgeCore" after the project file is replaced. Close that project window,
then run:

```sh
xcodebuild -project Forge.xcodeproj -scheme ForgePhotographer \
  -resolvePackageDependencies
```

Reopen `Forge.xcodeproj`; do not add the product manually or open `Package.swift` as the app project.
Confirmed 2026-08-18: package resolution and an unsigned generic iOS-device build both succeed from
the generated project.

---

## Session log

Newest first. One entry per working session. Keep entries short — what changed and what
the next agent needs to know, not a narrative.

### 2026-08-20 · Codex (GPT-5) — loopback `forge-server` slice

- Added `ForgeBridge` as a provider-neutral HTTP boundary and `forge-server` as the Mac-only
  composition root. The bridge owns request framing, multipart image extraction, stable responses,
  limits, and the `/health` + `/v1/plan` endpoint; only the executable imports
  `ForgeDirectorCodex`.
- The server hard-binds `127.0.0.1:8765`, processes one request at a time, supports
  `Expect: 100-continue`, accepts JPEG/PNG only, and exposes no prompt or shell surface. Provider
  errors are redacted; photographs and credentials are not logged.
- Six hardware-free endpoint tests cover health isolation, multipart success, routing, media type,
  provider error redaction, and declared-body framing. `make check` passes with 182 tests.
- Started the real server and verified both `curl /health` and a multipart upload of the user's cat
  image. The latter completed HTTP → sanitizer → installed Codex CLI → validated root
  `CompositionPlan` JSON with an animal selection, target frame, and three suggestions.
- Recorded D-13: no-auth is acceptable only on loopback. The next slice is a per-session development
  pairing token plus an explicitly enabled LAN listener and iPhone HTTP provider/selected-frame
  delivery. The current phone UI is unchanged and cannot reach the server yet.

### 2026-08-20 · Codex (GPT-5) — first real-AI Mac spike

- Recorded D-12: reuse the trusted development Mac's existing Codex CLI login; do not put OpenAI
  credentials in the iPhone app, repository, request payloads, or logs. This is a prototype path,
  not a production-backend commitment.
- Confirmed from the installed `codex-cli 0.144.6` help and the current official Codex manual that
  non-interactive execution supports JPEG/PNG input, JSON-schema-constrained final output,
  ephemeral sessions, and a read-only sandbox. The CLI credential store was deliberately not read.
- Added the isolated `ForgeDirectorCodex` module, strict `CompositionPlan` output schema, explicit
  `forge-director-codex-spike` executable, and `make codex-spike IMAGE=...`. Ordinary tests and CI
  compile the module but never invoke an external service.
- The provider re-encodes decoded pixels to a maximum-1024px JPEG without GPS/source metadata,
  stages generic temporary paths, suppresses raw CLI output, restricts the child environment,
  verifies response request identity, and applies core validation. Eight offline tests cover schema
  strictness, invocation isolation, environment filtering, decode/validation failures, request
  mismatch, input type, and metadata removal.
- The first real cat/room request passed: animal selection, anchor `[0.480, 0.380]`, target frame
  `[0.250, 0.310, 0.500, 0.310]`, three short suggestions, 13.28 seconds. This partially verifies
  V-6; stability and latency distribution remain open. `make check` passes with 176 tests.
- The user independently ran a second cat image through `make codex-spike`; it also passed with
  anchor `[0.526, 0.511]`, target frame `[0.176, 0.350, 0.606, 0.467]`, three suggestions, and
  10.19-second latency. Subject-agnostic coverage is still open because both runs selected animals.

### 2026-08-20 · Codex (GPT-5) — deterministic target frame on the live preview

- Added `PreviewGeometry` in `ForgeCapture`: a pure Forge-image-space → aspect-fill viewport mapper
  with orientation-corrected frame dimensions and explicit mirroring. Four asymmetric tests cover
  crop offsets, rotation-resolved portrait dimensions, mirroring, and invalid geometry.
- `CaptureModel` now publishes the latest frame geometry. `GuidanceOverlayView` uses the mapper for
  all spatial geometry and renders one deterministic target frame with a subdued outside scrim;
  detector rectangles, controls, AI selection, capture, and crop remain absent.
- `make check` passes with 168 tests; strict iOS type-check and the full simulator App build pass.
  The user accepted the physical-iPhone portrait result: one frame is visible, the outside scrim is
  restrained, and no rejected boxes returned. Landscape remains unchecked. Next is the
  privacy-sanitized planning-image/real Director-provider slice.

### 2026-08-20 · Codex (GPT-5) — remove rejected UI and double-box state

- Deleted the gray `GuidancePreviewScreen` and its Compose overlay, removed the live-HUD Compose
  entry point, and replaced the simulator fake scene with a direct camera-unavailable state.
- Removed `currentSubjectBounds`/`targetSubjectBounds` from `OverlayModel` and deleted their per-frame
  calculation in `GuidanceEngine`. The app status no longer exposes the human detection count.
- Kept the reusable camera/Vision pipeline and new subject-agnostic `visualAnchor`/`targetFrame`
  contract. Updated D-6 and the canonical UI skill: diagnostics must inspect perception separately.
- `make check` (164 tests), `make ios-typecheck`, and a separately generated full simulator App build
  pass. Simulator visual inspection confirms no synthetic Compose screen.
- After the user hit stale deleted-file references, regenerated the official project, resolved local
  packages, and verified a full formal-project build. The open Xcode window still requires restart.
- The user then verified the clean baseline on a physical iPhone. Removed the right-side “Ready”
  badge because the current core readiness state does not prove AI subject selection or a usable
  composition plan; the left “Camera ready” session-status badge remains. D-10 records the rule.
- Re-ran `make check` (164 tests), `make ios-typecheck`, and `make app`; all pass. Next remains one
  deterministic target frame over the real preview, with coordinate conversion tested separately.

### 2026-08-18 · Codex (GPT-5) — Xcode local-package refresh

- Investigated Xcode's "Missing package product ForgeCore" report. `Package.swift`, `project.yml`,
  and the generated PBX package/product references are correct; no source or product is missing.
- Explicit package resolution succeeded and an unsigned generic iOS-device build completed, proving
  this is stale Xcode-window state after XcodeGen replaced the open project, not a module failure.
- Recorded the non-destructive recovery above. No project source/configuration change was needed.

### 2026-08-18 · Codex (GPT-5) — agile slice 2b: one actionable frame

- Incorporated physical-phone feedback as D-9 before finalizing the UI: no normalized-coordinate
  sliders or stage picker; manual camera movement is the default and tapping the frame selects an
  optional post-capture crop.
- Stopped production `GuidanceOverlayView` from drawing the legacy current-subject and target-subject
  rectangles. Their geometry remains available internally for diagnostics.
- Made the single suggested frame a large accessible button with visible selected styling and an
  explicit "Auto crop" badge. This stores UI intent only; capture/crop output is still unbuilt.
- Updated `plan.md` and the canonical `ios-ui-design` overlay reference so future implementation
  preserves this interaction. Simulator screenshot confirms one frame and no sliders.
- `make check`, `make ios-typecheck`, and `make app` pass; 164 tests. Next action is physical-phone
  review of this refinement, then a separate still-capture/crop slice only after approval.

### 2026-08-18 · Codex (GPT-5) — agile slice 2: visible Compose preview

- Extended `OverlayModel`/`GuidanceState` and `GuidanceEngine` so visual anchor, target photograph
  frame, and display-only advice reach presentation state without prose-driven logic.
- Added `AIComposeOverlayView`: acquisition shows a fixed optical-centre reticle plus a distinct
  tracked anchor; framing shows one target boundary with an even-odd outside scrim.
- Repurposed the synthetic preview around a deterministic plan, two explicit stage controls, short
  advice, and adjustable anchor coordinates. The live HUD opens it through `Compose`; real capture
  and Vision remain unchanged.
- Visually checked both stages on the iPhone 16 Pro simulator and adjusted the sample frame/advice
  layout to avoid overlap. `make check`, `make ios-typecheck`, and `make app` pass; 164 tests.
- Reproduced the reported physical build failure: unsigned device compilation succeeds, while the
  signed build stops only because `FORGE_DEVELOPMENT_TEAM` is unset after project regeneration.
- Next action is physical-phone visual feedback, not more implementation.

### 2026-08-18 · Codex (GPT-5) — agile slice 1: composition contract

- Added schema-v1 `SubjectSelection`, forward-compatible `PhotographicSubjectKind`,
  `FramingPlan.targetFrame`, and display-only advice without changing existing callers or JSON.
- Extended field-level validation: anchors/confidence clamp; invalid rectangles drop; partially
  visible rectangles clip; already-valid geometry passes through exactly to avoid floating drift.
- Added fixtures, compact-wire/compatibility/degradation/round-trip tests, and static guards against
  branching on display-only advice or labels. 160 → 164 tests.
- `make check` and `make ios-typecheck` pass. No app UI or AI provider was changed in this slice.
- Next: deterministic app-side rendering of anchor → frame → advice from a fixture, then stop for
  device/simulator review before connecting a real image-capable Director.

### 2026-08-18 · Codex (GPT-5) — AI composition direction record

Recorded the user's physical-device product correction before touching implementation code.

- The app now has qualitative iPhone verification: live preview, human detection, overlay, and text
  cues render. The test exposed human-only semantics, unstable raw boxes, target geometry coupled to
  a bad detection, and incorrect aspect-fill overlay mapping.
- Confirmed D-5–D-7: AI proposes any photographic subject or scene theme from a selected image;
  local code tracks it; production UI acquires a visual anchor and then shows one target photograph
  frame; short prose is display-only.
- Updated `plan.md`, the `CompositionPlan` reference, and the guidance-overlay reference so future
  agents do not implement against the superseded two-box interaction.
- No production Swift was changed. Next is the contract-first step in the In flight list.

### 2026-08-16 · Claude Code (Opus 5) — session 3

Closed the Phase 2 vertical slice: real camera frames now reach guidance.

- **Fixed the red CI.** Swift 6.1 rejects a condition made unreachable by a `false` constant in an
  `#else` branch. The recovery path is now compiled only under `#if os(iOS)`, which is where it can
  actually run. Scanned for the same pattern elsewhere; the two other sites are safe.
- **`CapturePipeline`** — the spine, in `ForgeCore`. Applies `isCurrent` before analysis, keeps the
  three rates separate, and survives a failing director with the previous plan latched.
- **`ForgeVision`** — `VisionSceneAnalyzer` and `SubjectTracker`, with all Vision→domain coordinate
  conversion isolated in one file and tested with deliberately asymmetric fixtures.
- **App** — `CameraPreviewView` (session-driven, not frame-driven), `CaptureModel` as the composition
  root, `CaptureScreen` as the entry point.
- **Verified in the simulator**: permission prompt → `awaitingPermission` in the HUD → granted →
  `cameraUnavailable` with its recovery suggestion. The degradation design works through every layer.
- Removed a determinism violation: a `UUID()` request id reached `planId` and made two replays of the
  same session differ.

129 → 159 tests. Nothing verified on real hardware; that is now the top of the list.

### 2026-08-15 · Claude Code (Opus 5) — session 2

Took the stated next task: the capture lifecycle seam, plus the stale-frame limitation it flagged.

- **`CameraAuthorization` seam** (`status` + `requestAccess`), with `SystemCameraAuthorization`
  wrapping AVFoundation and a gated stub in the tests. Unknown authorization statuses resolve to
  denied rather than trusted.
- **Run identity** — `SceneFrame.runID`, `FrameSource.currentRunID`, and `isCurrent(_:)` resolve the
  buffered-stale-frame problem generally, for recorded sources as well as live capture. The
  composition root must apply `isCurrent` when it is written.
- **11 lifecycle tests**, all hardware-free: denial, restriction, refusal, no prompt when already
  authorized, concurrent starts, task cancellation, stop-during-prompt, background-during-prompt,
  and status publication. 129 → 144 tests.
- **`Tools/typecheck-ios.sh` + `make ios-typecheck`** replaces the documented manual incantation,
  and is verified to fail on planted errors in both a package target and the app.

Three of my own mistakes are recorded under Traps: a deadlocking single-slot test double, a zsh
quoting bug that made an iOS verification falsely report success, and a warning that only `make
test` catches. Nothing device-level is verified; `make app` still needs the iOS platform installed.

### 2026-08-15 · Codex (GPT-5)

Started Phase 2 with the camera-frame foundation. Added generic Foundation-only frame/analyzer
contracts, deterministic recorded replay, the neutral `ForgeFrame` ownership target, and an
AVFoundation source with bounded copies, rotation metadata, intrinsics, lifecycle status, and typed
errors. Added twelve tests (129 total), an iOS app compile lane, warnings-as-errors, a checksummed
XcodeGen install, and stronger boundary guards with permanent syntax fixtures. The package gates and
strict iOS type-check pass. Local app linking and every device/performance claim remain unverified;
next is lifecycle testability plus preview, then Vision and real UI wiring.

### 2026-08-15 · Claude Code (Opus 5)

Whole project from empty repo to Phase 1 complete.

1. **Planning** — wrote `plan.md` (phases, requirements F-xx/N-xx, guidelines, open
   decisions). `goal.md` was pre-existing and is untouched.
2. **Agent skills** — researched Codex and Claude Code skill mechanisms against official
   docs and by probing the Codex binary; verified discovery empirically with
   `codex debug prompt-input` (zero API cost) and `claude --debug`. Built six canonical
   skills in `.agents/skills/`, reached by Codex natively and by Claude Code through
   symlinks in `.claude/skills/`. `.agents/verify-skills.sh` validates the setup.
3. **Repo setup** — `.gitignore`, `README.md`, Apache-2.0 `LICENSE` + `NOTICE`.
4. **Phase 0** — `Package.swift`, `Makefile`, CI workflow, `Tools/check-boundaries.sh`,
   SwiftFormat/SwiftLint config.
5. **Phase 1** — the whole of `ForgeCore` and `ForgeTestSupport`, 117 tests.
6. **CI fixes** — replaced the org-licence-gated `gitleaks-action` with the MIT CLI,
   version and checksum pinned; aligned `make lint` with CI's `--strict`.
7. **XcodeGen (D-1)** — `project.yml`, app target, `GuidancePreviewScreen` driving the
   real pipeline from a synthetic scene.

Left for the next session: commit the outstanding work, then Phase 2.

---

## How to update this file

At the end of a session, do three things:

1. Refresh **Current state** and **In flight** so they describe reality.
2. Add a **Session log** entry: date, which agent, what changed, what is left.
3. Add to **Decisions** or **Traps** only when something is genuinely durable — a choice
   a future agent would otherwise reverse, or a mistake worth not repeating. Resist
   logging routine work here; that is what `git log` is for.

Keep the whole file readable in a couple of minutes. If a section grows past that,
either it belongs in `plan.md` or it has stopped being useful.
