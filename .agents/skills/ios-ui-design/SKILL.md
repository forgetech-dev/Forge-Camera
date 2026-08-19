---
name: ios-ui-design
description: Design and build AI Photographer's SwiftUI interface as a professional photography tool rather than a generic AI app — camera HUD, AI guidance overlay, subject placement and pose guides, settings strip, capture controls, connection and external-camera state, and the review screen. Enforces Apple Human Interface Guidelines, SF Symbols, semantic color, contrast over live imagery, one-handed reach, and purposeful motion. Use when building or reviewing any user-facing screen, overlay, control, or visual treatment. Do not use for capture-pipeline internals (use ios-camera) or guidance math (use vision-spatial).
license: Apache-2.0
metadata:
  project: ai-photographer
  last_verified: "2026-08-18"
  platform: "iOS 18+, SwiftUI"
---

# iOS UI Design for a Photography Tool

The interface must feel like a camera made by people who photograph, not like a chat product with a
viewfinder behind it. This skill is the standard every screen is held to.

## The one rule everything else serves

> **The camera preview is the primary content.**

Every pixel of persistent chrome is taken from the photograph. Justify it or remove it. The second
rule follows from the first:

> **AI direction must be the most visually dominant element after the image itself.**

If a user glances at the screen for 200 ms while composing, they must absorb the guidance without
reading. That is the design target.

## Hard prohibitions

These are rejected in review, not debated:

- The capture screen turned into a dashboard of cards and panels.
- Paragraphs of AI prose on the live view. Guidance is arrows, targets, outlines, and short labels.
- Decorative gradients, glows, or blurs with no functional purpose.
- Excessive corner rounding. Camera tools read as precise instruments; heavy rounding reads as a toy.
- Card-in-card-in-card stacking.
- Animations that exist to look modern. Motion must communicate state or direction.
- Generic "AI app" styling: purple-to-blue gradients, sparkle icons, chat bubbles, typing dots.
- Hardcoded black/white or fixed hex colors on anything that sits over live imagery.
- Controls placed where a thumb cannot reach one-handed while holding a phone at eye level.

## Layout model

Three zones, in priority order:

1. **The image.** Full-bleed preview. Nothing permanent on top of the frame's center.
2. **The guidance layer.** Transparent, over the image, spatially meaningful — target boxes, arrows,
   horizon line, pose overlay. Positioned *because* of where things are in the frame.
3. **The chrome.** Compact strips at the top and bottom edges. Settings, status, shutter.

Secondary complexity — full settings, capability inspectors, plan details, logs — lives behind a
deliberate gesture or sheet, never on the capture screen. Professional density is allowed *once the
user asks for it*.

## Component guidance

### Live camera HUD
Top edge: status only (connection, mode, thermal/degradation state, plan freshness). Bottom edge:
controls. Keep the vertical center clear. Prefer a single row of small monospaced-digit readouts over
a grid of labeled tiles.

### AI guidance overlay
The core of the product. Rules in [references/guidance-overlay.md](references/guidance-overlay.md).
Summary: at most one cue per actor (photographer / subject / camera), at most three on screen, each
one arrow-or-target plus a very short label. Never a sentence.

### Subject placement guides
In production AI Compose, first show the fixed optical-centre reticle and the Director's visual
anchor so the user can acquire the proposed subject or region. Once tracking is stable, show one
target photograph frame and subdue excluded content. Raw detection bounds and current/target subject
rectangles are diagnostics, off by default; they describe detector output rather than photographic
intent. Thirds grid is a toggle, off by default, and visually quieter than the AI target.

### Pose overlays
Skeleton overlays are diagnostic, not directive. Default them off. When guidance concerns pose, show
the specific joint or rotation involved, not the whole skeleton — a highlighted shoulder line with a
rotation arc beats 17 dots and 16 lines.

### Camera settings strip
Dense is acceptable here. Use monospaced digits (`.monospacedDigit()`) so values do not jitter as
they change. Show ISO / shutter / aperture / EV / focal length as compact readouts. Distinguish three
states visually: *read-only*, *app-controllable*, and *requires manual adjustment on the camera body*
— that last one is a real state in this project (`goal.md` §17) and needs a distinct treatment.

### Connection and external-camera state
Connection state is safety-critical information: the user must know whether the shutter will fire.
Use an explicit, persistent, low-noise indicator. Never rely on absence of an error as the signal for
"connected". Distinguish disconnected / connecting / connected / connected-but-degraded.

### Capture controls
The shutter is the largest, most reachable, most predictable control on the screen. It never moves,
never changes size, and never becomes contextual. Readiness state (from `GuidanceState.readiness`)
may change its *appearance*, but never its position or hit area.

### Review screen
Different mode, different rules — here the density can rise. Show the captured image large, with
detected issues as spatial annotations on the image plus a short list. A retake recommendation is a
primary action with the concrete deltas attached.

## Color, contrast, and legibility over live imagery

The background is arbitrary and changing: a bright sky, a black room, a busy street. This is the
hardest constraint in the whole interface.

- Use **semantic colors** (`Color.primary`, `.secondary`, `Material`) and system materials so the UI
  adapts to light and dark. Never hardcode hex on chrome.
- For anything drawn over the preview, contrast cannot come from color alone. Use one of: a thin
  contrasting outline/shadow on the shape, a material backing, or a subtle scrim behind text.
  A white arrow on a white wall is invisible; a white arrow with a 1pt dark outline is not.
- Meet WCAG-equivalent contrast for text; treat guidance graphics with the same seriousness.
- Never encode meaning in color alone — readiness, connection, and warnings all need a shape or
  glyph difference too. This covers both color-blind users and bright-sunlight viewing.

## SF Symbols and typography

- Use SF Symbols for controls and status. They inherit weight, scale, and Dynamic Type for free, and
  they carry the platform's visual language. Match symbol weight to the adjacent text weight.
- Prefer the system font. Use `.monospacedDigit()` for any number that updates live.
- Guidance labels are short, high-contrast, and consistently placed — not floating wherever the math
  put them.

## Accessibility

Support it where it is compatible with a viewfinder:

- **Dynamic Type** on all chrome and the review screen. The live overlay may cap growth to stay
  spatially meaningful, but must still respond.
- **VoiceOver**: guidance cues are meaningful spoken content ("Move left, about 40 centimeters").
  This is arguably the highest-value accessibility feature in the whole app — a guidance system that
  speaks direction is genuinely useful to a low-vision photographer.
- **Reduce Motion**: honor it. Directional motion becomes a static directional indicator.
- **Increase Contrast**: strengthen outlines and scrims.
- Hit targets ≥ 44×44 pt.

## Motion

Motion communicates or it does not ship.

- Legitimate: an arrow whose length/position reflects magnitude; a smooth transition when readiness
  is reached; a control appearing where it was summoned from.
- Illegitimate: entrance animations on status text, bouncing, pulsing "AI thinking" effects,
  parallax.
- Guidance overlays must be **smoothed but responsive**. The smoothing belongs in the guidance engine
  (see `vision-spatial`), not in the view — the view renders what it is given. A view-layer animation
  papering over jittery input hides a real bug.

## References

- [references/hig-camera-ui.md](references/hig-camera-ui.md) — HIG points that apply, SF Symbols,
  accessibility, official sources.
- [references/guidance-overlay.md](references/guidance-overlay.md) — the guidance overlay
  specification: cue budget, arrow semantics, precision display, readiness.

## Studying other camera apps

Halide, Blackmagic Camera, Leica LUX and similar tools are worth studying for *interaction patterns*:
how they keep the frame clear, how they surface dense settings without clutter, how they handle
one-handed reach. **Reference only.** Do not copy layouts, iconography, color systems, or any
proprietary asset. Describe the pattern in your own terms and design for this product's needs.

## Related skills

`ios-camera` (preview and capture plumbing), `vision-spatial` (what the overlay is allowed to claim),
`photography-director` (why a cue exists), `opensource-quality` (view/state boundaries).
