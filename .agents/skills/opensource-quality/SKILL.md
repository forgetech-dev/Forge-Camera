---
name: opensource-quality
description: Engineering standards for AI Photographer as a long-lived open-source project — module boundaries, shallow abstractions, explicit data flow, minimal dependencies, domain naming, small public APIs, Swift 6 concurrency, typed errors, structured logging, testability and mockability, hardware-free development, dependency and license hygiene, and privacy of keys and user photographs. Use for any cross-module or architectural change, any new abstraction, protocol, module or dependency, any naming or code-review question, and any change touching secrets, logging, or CI. Load this alongside the relevant domain skill for essentially all code changes.
license: Apache-2.0
metadata:
  project: ai-photographer
  last_verified: "2026-08-15"
  platform: "Swift 6, iOS 18+/macOS 15+"
---

# Open-Source Engineering Quality

`goal.md` §9's architecture rule is the whole of this skill in one line:

> **Clear boundaries, shallow abstractions, explicit data flow, minimal dependencies.**

The project optimizes for a new contributor understanding one part without reading the whole
repository. Understandable beats clever, every time.

## The balance

Modularity is a core requirement **and** abstraction-for-its-own-sake is a listed anti-goal
(`goal.md` §13, §23). These are not in conflict if the rule is:

> Create an abstraction when there is a **real or highly probable variation point**. Not before.

Real variation points in this project, each with a genuine second implementation:
`FrameSource` (phone / recorded / external), `CameraAdapter` (mock / Sony / future vendors),
`DirectorProvider` (heuristic / mock / hosted / BYOK / local), `SceneAnalyzer`, `MotionSource`.

That set is the **budget**. A sixth protocol needs a paragraph of justification naming its second
implementation.

## Module boundaries are compiler-enforced

Boundaries that exist only in a document erode. Express them as modules so the compiler enforces
them:

- The core domain imports **`Foundation` only**. It cannot import AVFoundation, Vision, ARKit,
  SwiftUI, or any vendor SDK — not by convention, by construction.
- Vendor code lives in vendor modules (`Camera/Sony/` or `ForgeCameraSony`). Provider code lives in
  provider modules.
- The UI layer talks to protocols, never to concrete adapters.
- A CI check greps for vendor identifiers (`Sony`, `Canon`, `Codex`, `OpenAI`) outside their owning
  modules and fails the build.

**Never silently bypass a boundary.** If a change seems to need one crossed, that is a design
discussion in the PR, not an import statement.

## Naming

Domain names, always:

```
CompositionPlan   GuidanceState   ExposurePlan   CameraCapabilities
DirectorProvider  SceneState      FrameSource    CameraAdapter
```

Banned unless the word genuinely is the role: `Manager`, `Helper`, `Utils`, `Processor`, `Handler`,
`Service`, `Thing`, `Data`, `Info`. `URLSessionDirectorTransport` is fine — it transports. `AIManager`
is not — it manages nothing specific.

Specifically prohibited by `goal.md` §23: a giant `AppState`, a giant `CameraManager`, a giant
`AIManager`, and a `Utils` dumping ground. If a type is hard to name, it usually does too much.

## Structure

- **Shallow.** Two levels of nesting inside a module. A third level means it is probably two modules.
- **Small public APIs.** Default to `internal`. `public` is a deliberate act, and every public symbol
  in the core carries a doc comment.
- **Value types by default.** Reference types only for identity or resource ownership.
- **Initializer injection.** Small protocols, constructed at one composition root. No singletons, no
  service locator, no DI framework (`goal.md` §13).
- **Pure engines.** Guidance, exposure, validation, and scene-change scoring have no I/O, no clock, no
  randomness, no logging side effects. Time and randomness are injected. This is what makes replay
  determinism possible.
- **Named constants.** Every threshold lives in a `*Policy` struct with a `.default`. No magic numbers
  scattered through logic; it also makes them sweepable in tests.

## Anti-patterns, explicitly

```
AbstractFactoryProviderManager        one protocol per trivial implementation
deep directory trees                  unnecessary factories or registries
hidden global state                   premature generic frameworks
giant *Manager types                  DI frameworks without demonstrated need
Utils dumping grounds                 clever code that is hard to read
```

Add: free-text AI responses used as application state; vision code changing camera settings; UI
issuing PTP commands; cloud AI on every video frame. All four are named in `goal.md` §23 and all four
are prevented by the module graph.

## Swift 6 concurrency

- Swift 6 language mode, strict concurrency, warnings as errors in CI.
- Domain types are `Sendable` value types. Stateful pipeline components are `actor`s.
- Frame delivery never touches the main actor. UI hops to `@MainActor` at the view-model boundary only.
- **Back-pressure by dropping**, buffer of one, latest wins. A queued frame is stale guidance.
- `@unchecked Sendable` requires a comment explaining the invariant that makes it safe.

## Errors

- Typed errors per module (`DirectorError`, `CameraError`, `CaptureError`). No stringly-typed
  failures, no `NSError` bridging in domain code.
- Errors a user can act on carry a recovery suggestion; errors they cannot are logged and degraded
  around.
- Never `try!`. `fatalError` only for genuine programmer errors.
- **Partial success is a real result.** `CameraAdapter.apply` returns a result per setting rather than
  throwing on the first failure — see `camera-integration`.

## Comments

Explain **why**, not what. A comment restating the code is noise that goes stale. Comments earn their
place when they record a decision, a non-obvious constraint, a workaround with a source, or an
invariant. Vendor quirks especially: cite the documentation or the observation that justified them.

## Testability is a hard requirement

> **A developer must not need a Sony A7C II, a Viltrox lens, an OpenAI API key, a Codex or Claude
> subscription, or any paid AI backend to run ordinary tests.**

This is a hard rule (`goal.md` §14), not an aspiration. `make build && make test` must be green on a
clean clone with no hardware, no keys, and no network.

Consequences the architecture must support:

- `MockCameraAdapter`, `MockDirectorProvider`, `RecordedFrameSource`, `ReplayCameraAdapter`,
  `RecordedSession` — mocks are written **first** and define the contract.
- Every adapter, mock and real, passes the same conformance suite.
- Hardware tests are isolated and explicitly invoked. External-service tests are isolated.
- Ordinary CI is deterministic — no network, no clock dependence, no randomness.

Details in [references/testing.md](references/testing.md). Do not implement these systems
speculatively; encode the requirement, and build each one when the code it tests arrives.

## Dependencies

Apple frameworks and the standard library first — that is why `goal.md` §13 prefers them, and it is
also the cleanest license position.

A new third-party dependency requires, in the PR description: what it solves, why the platform cannot,
its license and compatibility with ours, its maintenance status, and the cost of removing it later.
Expected count in the iOS app: **zero**. Dev-time tools (formatters, linters, project generators) are
held to a lower bar since they never ship.

Vendor SDKs carry licensing constraints that can prohibit inclusion outright — see
`camera-integration` → `references/licensing.md` before adding one.

## Logging, secrets, privacy

`OSLog`, one subsystem, one category per module. **Default `privacy: .private`**; `.public` is opt-in
and must be provably non-sensitive.

Never in source, git, logs, `UserDefaults`, analytics, or crash reports: API keys, image data, file
paths containing user content, precise location. Keychain for secrets, read at point of use.

User photographs are not stored or transmitted unnecessarily. Images sent to an AI provider are
downscaled, re-encoded, and stripped of EXIF/GPS, and a structured-state-only mode must exist and be
honored end to end. Details in [references/security-privacy.md](references/security-privacy.md).

## Definition of done

Every change:

- `make check` green (format, lint, build, test)
- tests for new behavior
- no new public API without a doc comment
- no new dependency without the justification paragraph
- no boundary crossed silently
- architecture docs updated if the module graph changed
- **run the appropriate build and tests after code changes** — never hand back unverified work

## References

- [references/testing.md](references/testing.md) — test tiers, mocks, recorded sessions, CI rules.
- [references/security-privacy.md](references/security-privacy.md) — secrets, logging, image data,
  permissions.

## Related skills

Load this alongside the relevant domain skill for essentially any code change: `ios-camera`,
`ios-ui-design`, `camera-integration`, `vision-spatial`, `photography-director`.
