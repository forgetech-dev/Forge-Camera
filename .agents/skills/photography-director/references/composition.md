# Photographic Composition — Reasoning Reference

**Purpose.** The photographic knowledge the Director reasons with, expressed as decisions that map
onto `CompositionPlan` fields. Written for an engineer implementing planning logic and prompts, not
as a photography course.

**Last verified:** 2026-08-15.

---

## Rules are defaults, not laws

Every guideline below is a strong default that good photographs routinely break. The schema must be
able to express a deliberate break (dead-center subject, horizon on the centerline, no lead room),
and the guidance engine must not "correct" it back toward the rule. A system that cannot break its
own rules produces competent, forgettable pictures.

The Director's job is to *choose*, then commit clearly enough that the guidance engine can act.

## Subject placement and scale

**Placement** (`targetX`, `targetY`). Thirds intersections are the default. Center works for
symmetry, confrontation, and formal portraits. The real driver is what else is in the frame — placement
exists to relate the subject to the background, not to satisfy a grid.

**Lead room.** A subject looking or moving toward frame-left is placed right of center, so the gaze
has space. Violating this creates tension — sometimes deliberately. This is a direct consequence of
`bodyYaw`/`headYaw`, so the two must be planned together, not independently.

**Headroom.** Scales with shot size. Tight portraits crop the top of the head; wide shots need air.
Too much headroom is the most common amateur error and one of the easiest to correct.

**Scale** (`targetHeight`) is a storytelling decision:

| Fraction of frame height | Reads as |
|---|---|
| ~0.9+ | Close portrait: expression, intimacy |
| ~0.6–0.8 | Half/three-quarter: person as subject, some context |
| ~0.3–0.5 | Environmental: person *in* a place |
| < 0.2 | Figure in landscape: scale, isolation |

Scale is set by **moving**, not zooming, unless the plan explicitly changes focal length — moving
changes perspective, zooming does not. See `vision-spatial` for the ratio math.

## Camera viewpoint

**Height** is the most underused variable and often the highest-leverage single change:

- Eye level — neutral, the default, and overused.
- Below eye level — subject gains stature; more sky/ceiling; can distort faces if close.
- Above eye level — subject diminished; more ground; flattering for some faces; good for separating a
  subject from a busy background.
- For children and animals, dropping to *their* eye level is usually transformative.

`heightAdjustment` is a fraction of subject height (see plan-schema.md), so "lower by 0.15" is
meaningful without knowing anything metric.

**Angle** (`yawAdjustment`) changes the relationship between subject and background more than it
changes the subject. This is the primary tool for background management — see below.

## Focal length

Focal length is a **perspective** decision, not a framing shortcut:

| Range | Character | Typical use |
|---|---|---|
| 24–35mm | Environmental, expansive; distortion near edges | Subject in a place; interiors; storytelling |
| 50mm | Close to natural perspective | General purpose |
| 85mm | Compression, flattering facial rendering, background separation | Portraits |
| 135mm+ | Strong compression, strong isolation | Tight portraits, candid distance |

With the reference primes (35mm and 85mm, no zoom), a focal-length recommendation is a **lens-change
request to the user**, not a camera command. The plan expresses intent; `camera-integration` decides
it is a manual request.

Because the reference rig has exactly two focal lengths, `recommendedFocalLength` should be
recommended sparingly — asking for a lens change is a large interruption and should only happen when
the improvement is large.

## Background management

Frequently the difference between a snapshot and a photograph, and the most common thing a novice
misses:

- **Intersections** — poles, branches, or lines emerging from the subject's head. Fixed almost always
  by **lateral movement** or a height change, not by rotation.
- **Bright/high-contrast distractions** — the eye goes to the brightest region. Reframe or reposition.
- **Merging tones** — subject and background at the same luminance kills separation. Change angle,
  height, or exposure priority.
- **Depth separation** — a wider aperture or longer focal length separates; both are constrained by
  camera capability.

`avoidRegions` in the plan expresses this. It is the schema's way of saying "the problem is over
there", which the guidance engine converts into a lateral or height correction.

## Pose and orientation

`bodyYaw` and `headYaw` are separate for a reason — the most useful portrait pose adjustments involve
turning the body while the head returns toward the camera.

- Body angled 20–45° from the camera is generally more dynamic than square-on. Square-on reads formal
  or confrontational.
- Head slightly different from the body creates natural tension; identical creates stiffness.
- Weight on the back foot, a slight lean, or an asymmetric stance reads as relaxed.
- Hands are the hardest part: something to do, or out of frame.
- Shoulders should not be level and square unless formality is the intent.

Pose guidance is **directed at the subject**, so it must be phrased as something a photographer can
say out loud to another person (`ios-ui-design`). "Body left 20°" is for the display; the human
translation matters.

## Genre priorities

Different intents rank the same variables differently. This is what `intent` selects.

| Intent | First priority | Then | Watch for |
|---|---|---|---|
| `portrait` | Subject scale, head/eye placement, background separation | Pose, light direction | Headroom, merging backgrounds |
| `environmental_portrait` | Subject-to-place relationship | Subject scale, background content | Subject lost in clutter |
| `landscape` | Horizon placement, foreground interest | Leading lines, depth layers | Tilted horizon, empty foreground |
| `street` | Moment and gesture | Layering, background timing | Over-correcting; the moment beats the composition |
| `architecture` | Verticals, symmetry, perspective | Viewpoint height | Converging verticals, keystoning |
| `group` | All faces visible and unobstructed | Even scale, depth alignment | Someone occluded, uneven rows |

## Horizon

Level unless deliberately tilted. Placement is a decision: high horizon emphasizes foreground, low
emphasizes sky. Center splits the frame and usually weakens it — unless symmetry or reflection is the
point.

Roll comes free and exact from gravity (`vision-spatial`), so horizon leveling is one of the few
metric-accurate cues available with no depth and no ARKit. It should be among the first things the
system gets right.

## Visual balance and negative space

- Visual weight comes from size, contrast, colour, and human presence — a small bright face outweighs
  a large dark shape.
- Negative space is active, not empty. Deliberate negative space is a compositional choice the schema
  must be able to express (via placement and scale) rather than something to be minimized.
- Leading lines and framing elements guide the eye; they are reasons to change viewpoint.

## Exposure intent

The Director emits **intent**; `ExposureEngine` produces values (`camera-integration`).

| Priority | Meaning |
|---|---|
| `subject` | Correct exposure on the subject; accept background clipping |
| `highlights` | Protect highlights; lift shadows later |
| `motion` | Shutter fast enough to freeze; accept ISO cost |
| `depth` | Aperture for the intended depth of field; accept shutter/ISO consequences |
| `balanced` | No strong preference |

Reciprocal-rule minimum shutter derives from focal length and is a floor, not an intent.

## Review and critique

Post-shot review looks for concrete, nameable, actionable defects: horizon error, subject placement,
distracting or intersecting background objects, pose problems, clipped highlights, soft focus,
unwanted motion blur, imbalance.

Two rules:

- **Actionable or silent.** A defect that cannot be expressed as a change to a retake plan is not
  worth reporting.
- **Willing to approve.** Review must be able to say "this is good, keep it". A critic that always
  finds something is noise, and users stop reading it.

## Open questions

- How should the Director handle multiple valid compositions of the same scene — commit to one, or
  offer a choice? Committing is simpler and more directive; offering may be more useful for learning.
- Should `intent` be inferred from the scene, chosen by the user, or both? Inference is magical when
  right and infuriating when wrong.
- How aggressively should a plan change when the subject moves substantially — is the target a fixed
  goal, or does it track the subject's new context?
