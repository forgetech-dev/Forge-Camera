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

**Last updated:** 2026-08-15 · **Phase:** 1 complete, 2 in progress

| | |
|---|---|
| Tests | 144, all passing |
| `make check` | Passing (format, lint, build, test, skills, boundaries) |
| CI | Baseline was passing; the new Xcode 16.4 app-build lane has not run remotely yet. |
| Hardware needed | None. `make build && make test` works on a clean clone with no camera, key, or network. |

### Built and verified

`ForgeCore` (Foundation only) —

- **Domain**: `NormalizedPoint`/`NormalizedRect` (top-left origin, y down), `Angle`,
  `FieldOfView`, `Measured<T>` with provenance, `SceneState` and detection types.
- **Director**: `CompositionPlan` + `PlanValidator` (field-level degradation),
  `DirectorProvider`, `HeuristicDirector`, `PlanTrigger`.
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

`ForgeCapture` — initial AVFoundation source: permission and lifecycle status, a serial session
queue, back-camera 1080p/NV12 configuration, RotationCoordinator, camera intrinsics delivery,
newest-one frame streaming, bounded buffer-copy pool, and typed actionable errors. Synthetic
sample-buffer tests verify ownership, metadata, drop accounting, and back-pressure without hardware.
Permission is now behind the `CameraAuthorization` seam, so the lifecycle races that matter —
concurrent starts, task cancellation, stopping mid-prompt, backgrounding mid-prompt — are pinned by
hardware-free tests.

`App` (3 files) — `ForgePhotographerApp`, `GuidanceOverlayView`,
`GuidancePreviewScreen`. The full Core → Frame → Capture → App graph passes a strict Swift 6
iOS-device-SDK type-check, but the screen still uses its synthetic scene.

### Not built yet

The Phase 2 vertical slice is not complete: there is no capture-owned preview bridge,
`ForgeVision`, real-frame composition root, session recorder, or device verification. F-01 is
therefore **not complete** even though its frame-source foundation exists. Everything from Phase 3
onward also remains unbuilt: network director, Mac bridge, review loop, and external-camera work.

---

## In flight

**Uncommitted work** — the first Phase 2 capture slice. All local hardware-free gates pass; it has
not been committed:

```
M .github/workflows/ci.yml  Makefile  Package.swift  README.md
M Tools/check-boundaries.sh  plan.md  project.yml
? Fixtures/boundaries/
? Sources/ForgeCore/Domain/SceneFrame.swift
? Sources/ForgeFrame/  Sources/ForgeCapture/
? Sources/ForgeTestSupport/RecordedFrameSource.swift
? Tests/ForgeCoreTests/FrameSourceTests.swift  Tests/ForgeCaptureTests/
```

**Next task:** keep Phase 2 moving without claiming hardware behavior prematurely:

1. ~~Permission/lifecycle seam plus hardware-free lifecycle tests.~~ **Done.**
2. Add the direct session-driven preview bridge. Load `ios-ui-design`, `ios-camera`, and
   `opensource-quality` because this crosses the capture/UI boundary.
3. Add `ForgeVision` (`VisionSceneAnalyzer`) and wire real frames through the composition root. Load
   `vision-spatial`, `ios-camera`, and `opensource-quality`.

The stale-buffered-frame limitation is **resolved**: `SceneFrame.runID` identifies the delivery run,
`FrameSource.currentRunID` reports the live one, and `FrameSource.isCurrent(_:)` is the check every
consumer must apply. A producer still cannot empty an `AsyncStream` buffer — the frame is now
recognisable rather than prevented — so **the composition root must call `isCurrent` in its consume
loop** when it is written. That is the one carry-over obligation into step 3.

Known and accepted: concurrent `start()` calls each query permission rather than sharing one
request. AVFoundation coalesces the visible prompt, so this is invisible to the user, and
deduplicating it would add machinery for no observable gain. `CaptureLifecycleTests` pins the
property that matters — all callers resolve and agree — rather than the call count.

---

## Blockers

**The local Xcode 16.0 install has no iOS 18 platform/runtime registered.** First-launch now works,
but `make app` and a generic device build both fail with “iOS 18.0 is not installed”; `simctl` lists
only watchOS 9. Install the iOS 18 platform/simulator through Xcode before relying on local app
builds. The current GitHub `macos-15` image does include Xcode 16.4 and an iOS 18.5 simulator, and CI
selects that version explicitly.

The workaround is now a script rather than an incantation to retype:

```sh
make ios-typecheck        # or ./Tools/typecheck-ios.sh
```

It compiles each package boundary in dependency order and type-checks `App/` against them, with the
device SDK, Swift 6, complete strict concurrency, and warnings as errors. It does **not** link or
produce a bundle, so it proves the code compiles, never that the app runs. Verified to fail on a
planted error in both a package target and the app.

**No Apple developer signing set up.** Zero signing identities, zero provisioning
profiles. A free Apple ID is sufficient for everything through Phase 5 — see the
2026-08-15 session note on licensing. Not needed until there is something to run on a
device.

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

**A single-slot continuation deadlocks multiple waiters.** A test double holding one
`CheckedContinuation` silently dropped all but the last concurrent caller, and the suite hung
instead of failing. Test doubles for concurrent code need a waiter list.

---

## Session log

Newest first. One entry per working session. Keep entries short — what changed and what
the next agent needs to know, not a narrative.

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
