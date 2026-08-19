# AI Guidance Overlay — Design Specification

**Purpose.** The guidance overlay is the product. This file specifies how it behaves visually, so
the treatment stays consistent as features are added.

**Last verified:** 2026-08-18.

---

## Design target

A photographer composing a shot glances at the screen for roughly 200 ms at a time, while holding a
camera, often in bad light, sometimes while talking to a subject. The overlay must be absorbed in
that glance, without reading.

This means: **shapes and positions carry the message; text only confirms it.**

## Cue budget

Hard limits, enforced in the guidance engine and assumed by the view:

- **At most one cue per actor** — photographer, subject, camera.
- **At most three cues on screen** total.
- Ranked by priority × normalized error; only the top cue per actor survives.

Rationale: a human cannot act on five simultaneous corrections. Showing all detected errors is
easier to build and worse to use. When many things are wrong, showing the single most important
correction is the actual feature.

## Actor distinction

Three actors, three visual treatments that are distinguishable at a glance without reading:

| Actor | Treatment |
|---|---|
| Photographer | Cues anchored to the screen edges — this is *you*, move yourself. |
| Subject | Cues anchored to the detected subject in the frame — move *them*. |
| Camera | Cues in the settings strip or as a frame-level indicator (level, height) — change the *device*. |

Never render a photographer cue and a subject cue in the same visual style. A user who moves
themselves when they should have moved the subject has been failed by the interface. In External
Camera Mode on a tripod, photographer and camera are genuinely different actors — the distinction is
not cosmetic.

## Precision display — the honesty rule

`GuidanceMagnitude` is either `.metric(meters:confidence:)` or `.relative(.slight/.moderate/.large)`.
The formatter switches on the case; there is no path that prints a number for a relative cue.

| Magnitude | Rendering |
|---|---|
| `.metric` | Direction glyph + value with unit: `← 40 cm`. Monospaced digits. |
| `.relative(.slight)` | Direction glyph + "a bit": `← Move left a bit` |
| `.relative(.moderate)` | Direction glyph + plain: `← Move left` |
| `.relative(.large)` | Direction glyph + emphasis: `← Move well left` |

Never invent a number. Never render a relative cue in a way that implies measurement (no progress
bars calibrated to nothing, no "≈35 cm"). `goal.md` §5 makes this a product requirement; the type
system makes it structurally impossible; this table makes it visually consistent.

Low-confidence metric values (below the policy threshold) render as relative. Confidence is not
shown as a number to the user — it decides the rendering, it is not itself content.

## Arrow semantics

An arrow's **length encodes magnitude** and its **direction encodes axis**. Both must be truthful:

- For `.metric` cues, length may scale continuously with the value.
- For `.relative` cues, length takes exactly three discrete values matching slight/moderate/large.
  A continuously varying arrow for a non-measured quantity is false precision by another route.
- Forward/backward (dolly) cannot be an in-plane arrow. Use a distinct glyph — a scaling indicator or
  a depth chevron — so it is never confused with lateral movement.
- Rotation cues use an arc, never a straight arrow.

## AI Compose interaction — visual anchor, then target frame

Physical-device validation replaced the original two-subject-box presentation. Raw detection bounds
answer "what did the detector find?"; they do not answer "what photograph should I make?" They are
diagnostics and are off in the production interface.

The production interaction has two spatial stages:

1. **Acquire the AI selection.** A fixed optical-centre reticle represents where the camera is aimed.
   A distinct visual-anchor marker identifies the compositional attention point chosen by the
   Director — for example, a cat's eyes, a person's face, or an architectural vanishing point. The
   user brings the two together to acquire the proposed subject or region. This is not yet the final
   composition, and the visual anchor is not automatically an autofocus point.
2. **Compose the photograph.** Once local tracking is stable, replace acquisition emphasis with one
   target photograph frame. Subdue content outside it with a restrained scrim. The frame describes
   the desired photograph boundary; it is never derived from or presented as a subject bounding box.

The user can tap a different subject or region to replace the AI proposal. The new choice rebinds
local tracking; it does not require parsing any text.

Horizon and other spatial cues may coexist only when they materially help and remain within the cue
budget. Preview mapping must account for aspect-fill cropping, rotation, and mirroring; multiplying
normalized coordinates by SwiftUI view size is valid only when preview and view share an aspect
ratio.

## Short shot advice

The Director may provide a concise, display-only explanation such as a subject/theme label plus one
current suggestion. Keep it to at most two short lines over the live preview. It appears on a system
material near an edge, never as a paragraph over the subject, and collapses once the user has
understood the plan.

Structured geometry and typed cues remain the only application state. The UI may display
`rationale` or `displayAdvice`; no engine or view model may branch on their wording.

## Stability

The overlay renders what the guidance engine gives it. The engine applies smoothing, deadband,
hysteresis, and a minimum cue duration. The view must **not** add its own animation to disguise
jitter — that hides a real bug and adds lag.

The only legitimate view-layer motion is a short transition when a cue is replaced or when readiness
changes state, so the change is noticed rather than missed.

## Readiness

`readiness` has three states and each needs an unmistakable, glanceable treatment:

| State | Treatment |
|---|---|
| `.blocked` | The blocking cue is shown prominently. Shutter appearance indicates not-ready. |
| `.close` | Cues shrink in emphasis; a "nearly there" indication appears. |
| `.ready` | Cues clear. A single unambiguous ready indication. Optionally a haptic. |

Reaching `.ready` is the emotional payoff of the whole product. It should feel decisive: the screen
gets quieter, not busier. Resist the urge to add a celebration — the reward is the clear frame.

A haptic on `.ready` is genuinely useful because the user is looking at the scene, not the screen.
Use it, honor Reduce Motion / system haptic settings, and never fire it repeatedly as the state
oscillates — the engine's hysteresis is what makes a haptic tolerable.

## Degradation states the overlay must express

Per `goal.md` §17, these are normal states and each needs a visual:

- No AI backend → guidance continues from local heuristics; indicate the source is local.
- No metric data → all cues relative; no unit text anywhere.
- Unknown focal length → prompt for manual entry rather than silently degrading angular cues.
- Setting not writable by the app → cue is addressed to the user as a manual adjustment, visually
  distinct from cues the app can act on.
- Plan stale or in-flight → indicate plan freshness subtly; never block on it.
- No clear subject/theme → say that the system is unsure and invite the user to tap a subject or
  reframe; never invent a confident target frame.

## Open questions

- Optimal discrete arrow lengths for slight/moderate/large — needs user testing, not a guess.
- Whether subject-directed cues should ever be shown to the *subject* (e.g. a second screen or a
  flipped display) rather than narrated by the photographer.
- Whether continuous VoiceOver guidance is usable during composition or too intrusive.
