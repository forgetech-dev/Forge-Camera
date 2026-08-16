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

**Last updated:** 2026-08-15 · **Phase:** 1 complete, 2 not started

| | |
|---|---|
| Tests | 117, all passing |
| `make check` | Passing (format, lint, build, test, skills, boundaries) |
| CI | Passing |
| Hardware needed | None. `make build && make test` works on a clean clone with no camera, key, or network. |

### Built and verified

`ForgeCore` (Foundation only, 18 files) —

- **Domain**: `NormalizedPoint`/`NormalizedRect` (top-left origin, y down), `Angle`,
  `FieldOfView`, `Measured<T>` with provenance, `SceneState` and detection types.
- **Director**: `CompositionPlan` + `PlanValidator` (field-level degradation),
  `DirectorProvider`, `HeuristicDirector`, `PlanTrigger`.
- **Guidance**: `GuidanceState`, `GuidanceEngine` (+`GuidanceEngine+Cues`),
  `GuidanceCueFormatter`.
- **Exposure**: `ExposureCapabilities`, `ExposureEngine`.
- **Policies**: `GuidancePolicy`, `ExposurePolicy`, `PlanTriggerPolicy`.

`ForgeTestSupport` — `SceneFixtures`, `PlanFixtures`, `MockDirectorProvider`,
approximate-equality helpers.

`App` (3 files) — `ForgePhotographerApp`, `GuidanceOverlayView`,
`GuidancePreviewScreen`. Type-checked against an iOS-built `ForgeCore`, but see the
blocker below.

### Not built yet

Everything from `plan.md` Phase 2 onward: AVFoundation capture, Vision analysis, the
real camera pipeline, any `DirectorProvider` that talks to a model, the Mac bridge, and
all external-camera work. `ForgeVision`, `ForgeCapture`, `ForgeDirector`, `ForgeBridge`,
`ForgeCameraSony`, and `forge-server` exist in the plan only — there are no such targets
in `Package.swift`.

---

## In flight

**Uncommitted work** — Phase 1 completion plus the XcodeGen setup. All gates pass; it
simply has not been committed yet:

```
M .gitignore  .swiftlint.yml  Makefile  Sources/ForgeCore/Director/CompositionPlan.swift
? App/  project.yml
? Sources/ForgeCore/{Director/PlanTrigger,Guidance/GuidanceCueFormatter}.swift
? Sources/ForgeCore/Exposure/  Sources/ForgeCore/Policies/{Exposure,PlanTrigger}Policy.swift
? Tests/ForgeCoreTests/{ExposureEngine,GuidanceCueFormatter,PlanTrigger}Tests.swift
```

**Next task:** Phase 2 — the iOS camera pipeline. Start with `ForgeCapture`
(`AVFoundationFrameSource` behind the `FrameSource` protocol), then `ForgeVision`
(`VisionSceneAnalyzer`), then replace `GuidancePreviewScreen`'s synthetic scene with
real frames. Load the `ios-camera` and `opensource-quality` skills for that work.

---

## Blockers

**`xcodebuild` does not run on this machine.** Xcode's first-launch components were
never installed, so `xcodebuild` fails on *every* destination — simulator and device
alike — with a plugin-loading error. `devicectl` is missing for the same reason.

Fix (needs admin, the user must run it):

```sh
sudo xcodebuild -runFirstLaunch
```

Until then `make app` is unproven. The workaround used so far, which does work and does
catch real errors, is to compile the core for iOS and type-check the app against it:

```sh
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
xcrun swiftc -sdk "$SDK" -target arm64-apple-ios18.0 -emit-module \
  -emit-module-path /tmp/ForgeCore.swiftmodule -module-name ForgeCore \
  $(find Sources/ForgeCore -name '*.swift')
xcrun swiftc -sdk "$SDK" -target arm64-apple-ios18.0 -typecheck -I /tmp App/*.swift
```

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
it.

**Measure exit codes, not `tail`'s.** `cmd | tail -1; echo $?` reports the exit status of
`tail`. This produced two wrong "it passes" conclusions in one session.

---

## Session log

Newest first. One entry per working session. Keep entries short — what changed and what
the next agent needs to know, not a narrative.

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
