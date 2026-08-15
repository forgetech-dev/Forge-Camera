---
name: photography-director
description: Photographic reasoning and AI planning for AI Photographer — deciding what the target photograph should be, expressed as a structured CompositionPlan rather than prose. Covers portrait, environmental portrait, landscape, street and architectural composition, subject placement and scale, pose and body/head orientation, camera viewpoint, height, angle and focal length, background management, visual balance, horizon, exposure intent, event-driven replanning, post-shot critique and retake recommendation, plus DirectorProvider design, schema validation, and planning cadence. Use when working on the AI Director, composition rules, plan schema, prompts, providers, or review and retake logic.
license: Apache-2.0
metadata:
  project: ai-photographer
  last_verified: "2026-08-15"
---

# AI Photography Director

The Director decides **what the photograph should be**. It does not fly the camera.

## The split that defines the system

```
AI Director          slow    0.2–2 Hz    "the subject belongs here, at this scale, turned this way"
Local Vision         fast    15–60 FPS   "the subject is currently here"
Guidance Engine      fast    15–60 FPS   deterministic control: current → target
```

Three rules follow, and they are architectural, not stylistic:

1. **The AI never drives realtime tracking.** Perception is local (`vision-spatial`).
2. **The AI is never called per frame.** Replanning is event-driven (see cadence below).
3. **The AI emits a target state; local code computes the corrections.** The Director says where the
   subject should be; the guidance engine says "move left". The Director never says "move left".

A `CompositionPlan` is **latched state**, not an event. Guidance reads the current plan every frame.
A slow, failed, or absent plan never stalls the loop — it means guidance runs on the previous plan,
or on `HeuristicDirector`.

## Structured output only

> **Free-text AI responses are never application state.** (`goal.md` §23)

The Director returns a validated `CompositionPlan`. Every field is typed. The one prose field,
`rationale`, is **display-only**: it is shown to the user and **no engine, view model, or test may
branch on its content**. That is the enforcement mechanism, and it is checkable in review.

Schema, field semantics, validation rules, and the unit decisions that `goal.md`'s example leaves
ambiguous are in [references/plan-schema.md](references/plan-schema.md). Two that matter most:

- **Absent ≠ zero.** A missing `heightAdjustment` means "no opinion", not "stay put". Every optional
  field is `Optional`, and engines must distinguish the two.
- **Field-level degradation.** An out-of-range `targetX` drops *that field* and keeps the rest of the
  plan. Plans are not all-or-nothing.

## Representing uncertainty

The Director must be able to say "I am not sure", and the system must do something sensible with it.

- `confidence` on the plan, and per-field where meaningful.
- Low confidence → weaker cues, wider tolerances, no aggressive corrections. It does not mean hide the
  plan; it means hold it more loosely.
- A Director that cannot see enough to decide should return a **minimal plan** (say, subject placement
  only) rather than a confident full plan built on guesses.
- Never present a low-confidence plan with the same visual authority as a high-confidence one
  (`ios-ui-design`).

Hidden uncertainty is the failure mode that makes an assistant untrustworthy.

## Planning cadence

Replan only when one of these fires, under a hard rate cap with a single in-flight request (new
requests coalesce, they never queue):

| Trigger | Rationale |
|---|---|
| No plan latched | cold start |
| Plan older than `expiresAfterSeconds` | staleness |
| Material scene change | subject count changed, tracked subject moved > ~15% of frame, scene luma shifted > ~1 EV, camera moved > ~0.5 m, focal length changed |
| User asked | always allowed; resets the limiter |
| Capture completed | drives review → retake |

Scene-change scoring is a **pure function of two `SceneState`s** — trivially unit-testable, and the
main lever on both AI cost and perceived stability. Replanning too eagerly makes guidance feel
unstable; the user experiences a jittery target as the system changing its mind.

## `HeuristicDirector` — one implementation, two jobs

A deterministic, offline `DirectorProvider` implementing rule-of-thirds placement, horizon leveling,
headroom, and lead room. It is simultaneously:

- the **no-backend degradation path** (`goal.md` §17), and
- the **test double** for every guidance and replay test.

One implementation means offline behavior cannot drift from what tests exercise, and it means a
useful product exists before any AI does. Build it first.

## Provider design

```swift
protocol DirectorProvider: Sendable {
    func plan(_ request: DirectorRequest) async throws -> CompositionPlan
    func review(_ request: ReviewRequest) async throws -> ReviewResult
}
```

- Vendor specifics stay inside the provider. Prompts, schema coercion, retries, and model names never
  leak into the domain (`goal.md` §13).
- Use the provider's **structured/constrained output** where available. Do not parse prose.
- **One** repair retry on validation failure, with the error appended. If it fails again, throw; the
  previous plan stays latched. No repair loops.
- Timeouts, a token/request budget, and a visible cost counter. An assistant that quietly spends money
  is a bad assistant.
- Send the minimum: structured `SceneState` plus, when needed, one downscaled image (longest edge
  ~1024 px) with EXIF and GPS stripped. A "structured state only, no images" mode must exist and be
  honored (`goal.md` §16).

## Exposure: intent vs implementation

Kept conceptually separate, and separate in code:

- The Director expresses **intent** — "prioritize the subject", "protect highlights", "freeze motion".
- `ExposureEngine` turns intent into concrete values, clamped to `CameraCapabilities`.

The Director must not emit "ISO 800" as if it knows the camera; it emits a priority. This is what
lets the same plan work on a phone and on a mirrorless body with a different sensor and a different
supported ISO set. See `camera-integration`.

## Post-shot review and retake

Review runs on the **full-quality capture**, not the live-view frame (`goal.md` §8). It detects
concrete, nameable defects — horizon error, subject placement, distracting or intersecting background
objects, pose problems, clipped highlights, soft focus, unwanted motion blur, imbalance — and returns
a `ReviewResult`.

A retake recommendation is a `CompositionPlan` again, so the retake path reuses the entire guidance
loop rather than being a separate feature. Closing the loop this way is the point of the whole
architecture.

Review must be willing to say **"this is good, keep it"**. A reviewer that always finds something is
noise.

## Photographic knowledge

Composition, subject placement, pose, viewpoint, focal length, background, and balance guidance —
the actual photographic content — is in [references/composition.md](references/composition.md).
Prompt-relevant framing and genre-specific priorities live there.

Rules are **defaults, not laws**. A good plan may deliberately break the rule of thirds; the schema
must be able to express that, and the guidance engine must not "correct" it back.

## Research grounding

Relevant published work — ShutterMuse, Smart Point-and-Shoot, Before the Shutter, CameraBench — with
what each contributes and what to be careful about, is in
[references/research.md](references/research.md). Useful for benchmark design, taxonomy, and prior
art; not a substitute for the product's own decisions.

## References

- [references/plan-schema.md](references/plan-schema.md) — the CompositionPlan contract and validation.
- [references/composition.md](references/composition.md) — photographic reasoning by genre.
- [references/research.md](references/research.md) — primary literature with citations.

## Related skills

`vision-spatial` (what the plan is measured against), `ios-ui-design` (how a plan becomes visible),
`camera-integration` (capability limits on exposure), `opensource-quality` (provider boundaries,
determinism, mocks).
