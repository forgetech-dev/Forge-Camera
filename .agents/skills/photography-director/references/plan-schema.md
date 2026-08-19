# CompositionPlan — Contract and Validation

**Purpose.** The interface between the AI Director and everything else. This is the most important
contract in the project: it is the boundary where an untrusted, non-deterministic component meets
deterministic application state.

**Last verified:** 2026-08-18.

---

## Wire format (schemaVersion 1)

```json
{
  "schemaVersion": 1,
  "planId": "6f1c…",
  "requestId": "a92e…",
  "intent": "environmental_portrait",
  "confidence": 0.82,
  "rationale": "Backlit subject; place off-center to include the archway.",
  "selection": { "kind": "animal", "label": "cat",
                 "sourceRegion": [0.38, 0.31, 0.30, 0.42],
                 "visualAnchor": [0.49, 0.39], "confidence": 0.91 },
  "framing":  { "targetFrame": [0.18, 0.16, 0.64, 0.72] },
  "displayAdvice": ["Use the cat's eyes as the visual anchor."],
  "subject":  { "targetX": 0.64, "targetY": 0.48, "targetHeight": 0.66,
                "bodyYaw": -20, "headYaw": 5, "poseHint": "weight_on_back_foot" },
  "scene":    { "targetHorizon": 0.34, "avoidRegions": [[0.0, 0.0, 0.2, 0.4]] },
  "camera":   { "heightAdjustment": -0.15, "yawAdjustment": 7,
                "recommendedFocalLength": 35 },
  "exposure": { "priority": "subject", "apertureHint": 2.8, "minShutterDenominator": 250 },
  "capture":  { "kind": "bracket", "stops": [-2, 0, 2] },
  "expiresAfterSeconds": 20
}
```

Required: `schemaVersion`, `planId`, `intent`. **Everything else is optional.**

## Subject selection and target framing

Physical-device validation showed that a plan centered on a pre-detected human and a target human
box is too narrow. The Director must first decide **what photograph is worth making**. The contract
therefore includes these additive schema-version-1 fields:

```json
{
  "selection": {
    "kind": "animal",
    "label": "cat",
    "sourceRegion": [0.38, 0.31, 0.30, 0.42],
    "visualAnchor": [0.49, 0.39],
    "confidence": 0.91
  },
  "framing": {
    "targetFrame": [0.18, 0.16, 0.64, 0.72]
  },
  "displayAdvice": [
    "Use the cat's eyes as the visual anchor.",
    "Lower the camera and exclude the monitor."
  ]
}
```

- Selection covers people, animals, objects, places, scene-level themes, and the valid result that
  there is no clear discrete subject.
- `sourceRegion` and `visualAnchor` describe the selected planning image in Forge normalized space.
  Local perception uses them to initialize tracking and owns the stable runtime identity.
- `visualAnchor` is a compositional attention point. It is not automatically an autofocus point.
- `targetFrame` is the proposed photograph boundary, not a subject bounding box.
- The user can replace the proposal by tapping a different subject or region.
- AI planning happens on one selected, sanitized image. Local tracking runs per frame; the AI does
  not.
- `label`, `displayAdvice`, and `rationale` are display-only. No engine, view model, or test may
  branch on their content.

## Unit decisions

`goal.md` §4's example leaves two units undefined. These are the binding resolutions:

| Field | Unit | Why |
|---|---|---|
| `targetX`, `targetY` | Forge normalized frame space, `[0,1]`, origin top-left | Matches the project-wide convention (`vision-spatial`). |
| `targetHeight` | Subject bounding-box height as a **fraction of frame height** | Scale-free; comparable across cameras and lenses. |
| `heightAdjustment` | **Fraction of the subject's on-screen height**, dimensionless | See below. |
| `bodyYaw`, `headYaw`, `yawAdjustment` | Degrees, positive counter-clockwise (right-hand rule); `0` faces the camera | Project-wide angle convention. |
| `targetHorizon` | Normalized y of the horizon line | Same space as `targetY`. |
| `avoidRegions` | Array of `[x, y, w, h]` in normalized space | Regions that should not contain the subject or distracting content. |
| `sourceRegion`, `targetFrame` | `[x, y, width, height]` in Forge normalized planning-image space | Must remain independent: one locates the selected content, the other defines the desired photograph. |
| `visualAnchor` | `[x, y]` in Forge normalized planning-image space | Compositional attention point used to acquire and track the AI selection. |
| `recommendedFocalLength` | Millimeters, 35mm-equivalent | Must be snapped to what the camera/lens supports. |
| `expiresAfterSeconds` | Seconds | Staleness trigger for replanning. |

### Why `heightAdjustment` is dimensionless

A metric field would force the model to guess a scale it cannot see. From a single image, an MLLM has
no reliable way to know that lowering the camera "15 cm" is right — but it can reliably judge "lower
by about 15% of the subject's height", because that is a purely visual relationship.

The value converts to centimetres only when the subject's real height is independently known, exactly
the same pattern as the dolly-ratio result in `vision-spatial`. Scale-free intent in; units attached
later, only if earned.

## Validation rules

Implemented as a pure function in the core, unit-tested against a fixture corpus of valid and
malformed plans.

1. **Hard reject** if `schemaVersion` major differs, or `planId`/`intent` is missing or empty.
2. **Field-level degradation otherwise.** An invalid field is dropped with a logged warning; the rest
   of the plan survives. Plans are not all-or-nothing — a good subject placement should not be lost
   because the model emitted a silly focal length.
3. Clamp normalized values to `[0,1]`. Reject `NaN` and `±inf` — a `NaN` that reaches the guidance
   engine poisons every downstream computation silently.
4. Wrap angles into `(-180, 180]`.
5. Snap `recommendedFocalLength` to the connected lens/camera's supported range; drop it if focal
   length is unknown and no manual value was entered.
6. Unknown enum values (`intent`, `selection.kind`, `poseHint`, `capture.kind`,
   `exposure.priority`) decode to `.unknown(String)` and are ignored by engines. Forward
   compatibility without a schema bump.
7. Unknown top-level keys are ignored, never an error.
8. Reject `avoidRegions` entries that cover more than a policy fraction of the frame — a model that
   says "avoid everything" has failed, and acting on it produces nonsense guidance.
9. Preserve already-valid selection/framing geometry exactly. Clip partially visible rectangles;
   drop non-finite, non-positive, or fully outside geometry at field level.

## Absent is not zero

The single most consequential rule. Every optional field is `Optional` in Swift, and engines must
distinguish:

- `heightAdjustment == nil` → the Director has no opinion → **emit no camera-height cue**.
- `heightAdjustment == 0.0` → the Director explicitly says the current height is right → may emit a
  "hold" confirmation.

Decoding a missing field to a default of `0` collapses these into one, and produces confidently wrong
guidance that is very hard to trace back to its cause.

## Plan prose is display-only

`rationale`, `selection.label`, and `displayAdvice` may be shown to the user. **No engine, view
model, or test may branch on their content.**

This is the concrete enforcement of `goal.md` §23's prohibition on free-text AI responses as
application state. It is greppable in review: semantic inspection such as `rationale.contains(...)`
or `displayAdvice.contains(...)` is an automatic rejection.

## Versioning

- `schemaVersion` is an integer. Major mismatch → reject; the client is too old or too new.
- Additive changes (new optional fields) do not bump the version — rule 7 handles them.
- Provider prompts embed the schema, so a schema change and a prompt change ship together.
- Recorded sessions store the schema version so replays remain interpretable.

## Provider-side generation

Getting valid JSON out of a model is the **provider's** job, not the core's:

- Use structured / JSON-schema-constrained output where the provider supports it.
- Low temperature. Plans should be stable across near-identical scenes; an unstable plan produces a
  target that visibly moves while the user is trying to reach it.
- Exactly **one** repair retry, with the validation error appended. Then throw.
- Never "fix up" a bad plan with heuristics inside the provider — that hides model failures and makes
  provider comparison meaningless. Let it fail and let `HeuristicDirector` take over.

## Test corpus

The fixture set that must exist, because these are the failures that actually happen:

- Valid plans across every intent.
- Missing required fields.
- Out-of-range normalized values; negative sizes.
- `NaN` / `Infinity` / string-where-number.
- Unknown enum values; unknown extra keys.
- Empty object; empty string `planId`.
- A plan valid in isolation but impossible for the connected camera (unsupported focal length).
- A plan where every optional field is absent — must produce a valid, minimal plan.
- Adversarial `rationale` containing text that looks like instructions.
- Person, animal, object, and scene-theme selections, including a selection with no discrete bounds.
- A malformed or out-of-frame `sourceRegion`, `visualAnchor`, and `targetFrame`, each degrading at
  field level without discarding independent valid advice.
- Adversarial `displayAdvice` that looks like application commands; it remains display-only.

Golden tests assert the exact validated result, so a validation change is a visible diff.

## Open questions

- Should `confidence` be per-field rather than per-plan? Per-field is more expressive but more for the
  model to get wrong.
- Should `avoidRegions` distinguish "do not place the subject here" from "this region is distracting
  and should be excluded from frame"? They imply different corrections.
- How should two plans be blended when a new plan arrives mid-correction — snap, or interpolate? Snap
  is simpler and more predictable; interpolation is smoother but can make the target feel evasive.
