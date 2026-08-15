# HIG, SF Symbols, and Accessibility for a Camera UI — Project Reference

**Purpose.** The Apple guidance that actually constrains this app's interface, plus the places where
a camera app legitimately departs from ordinary iOS app conventions.

**Last verified:** 2026-08-15 against iOS 18 HIG.

---

## Where a camera app departs from ordinary iOS patterns

Most iOS design guidance assumes content that scrolls under chrome. A viewfinder does not. The
legitimate departures:

- **Full-bleed content with edge-anchored controls** rather than a navigation stack. There is no
  navigation bar on the capture screen.
- **Persistent dark treatment** for chrome regardless of system appearance, because the surrounding
  UI should not blow out the user's dark adaptation or compete with the image. This is the one place
  where committing to a fixed appearance is defensible — but the *values* still come from semantic
  colors and materials, not hardcoded hex.
- **Gestures over buttons** for secondary functions (swipe for modes, tap-to-focus, drag for
  exposure). Standard camera vocabulary; do not reinvent it.

Everything else follows the HIG normally.

## HIG points that bind this project

**Clarity, deference, depth.** Deference is the operative one: the interface defers to the
photograph. Any element that competes with the image loses.

**Touch targets.** Minimum 44×44 pt. Non-negotiable for the shutter and mode controls.

**Reachability.** Primary controls in the bottom third. The top edge is for status the user reads,
not controls the user presses. A phone held at eye level in one hand has a thumb arc covering
roughly the bottom half of the screen.

**Feedback.** Every capture needs immediate confirmation independent of processing time — the user
must know the shot was taken before the image is ready.

**Consistency.** Use system gestures and system controls where they exist. A custom slider that
behaves almost like a system slider is worse than the system slider.

**Materials.** `.regularMaterial` / `.thinMaterial` give legibility over unpredictable backgrounds
while preserving context. Prefer these over flat translucent fills for chrome backing.

## SF Symbols

- Ship with the OS, inherit text weight/scale, support Dynamic Type and accessibility settings, and
  carry platform-native meaning. Use them for controls and status.
- Match the symbol's weight to adjacent text weight so a row reads as one unit.
- Use `.symbolRenderingMode(.hierarchical)` or `.palette` for state differentiation instead of
  inventing new glyphs.
- Symbol *variants* (`.fill`, `.slash`, `.circle`) are the idiomatic way to express state — a
  `.slash` variant communicates "unavailable" more clearly than a color change, and works in
  sunlight and for color-blind users.
- Always set an accessibility label; a symbol alone is not a name.

## Color and contrast over live imagery

The single hardest constraint: the background is arbitrary and changes continuously.

- Semantic colors (`.primary`, `.secondary`, `.accentColor`) and materials adapt; hex does not.
- Guidance graphics need **shape-level contrast insurance**: a contrasting outline, a drop shadow, or
  a scrim. Relying on the color alone fails against a matching background.
- Never encode meaning in color alone (HIG accessibility requirement and a practical sunlight
  requirement). Pair every color state with a glyph or shape difference.
- Test the overlay against four backgrounds at minimum: bright sky, dark interior, mid-grey wall,
  and a high-frequency busy scene.

## Accessibility

| Feature | Requirement here |
|---|---|
| Dynamic Type | Full support on chrome and review screen. Live overlay may cap growth but must respond. |
| VoiceOver | Guidance cues are spoken direction — a first-class feature, not an afterthought. Label every control. |
| Reduce Motion | Directional animation becomes static directional indication. |
| Increase Contrast | Strengthen outlines and scrims on overlay elements. |
| Differentiate Without Color | Already required by the color rule above. |
| Voice Control | Controls need sensible names; the shutter must be addressable. |

`@Environment(\.accessibilityReduceMotion)`, `\.accessibilityDifferentiateWithoutColor`, and
`\.dynamicTypeSize` are the SwiftUI hooks.

## SwiftUI implementation notes

- The overlay observes a small `Sendable` value type (`GuidanceState`). It does not observe the
  camera, the analyzer, or a global app state object.
- Per-frame updates must not invalidate the whole view tree. Scope observation tightly; a
  `Canvas` or a dedicated overlay view redrawing is fine, the whole screen re-rendering is not.
- `AVCaptureVideoPreviewLayer` reaches SwiftUI through `UIViewRepresentable`. Keep that wrapper
  minimal and free of logic.
- `.monospacedDigit()` on every live-updating number, or readouts jitter distractingly.
- `drawingGroup()` can help complex overlays, but measure — it is not free and can hurt.

## Official sources

- Human Interface Guidelines: https://developer.apple.com/design/human-interface-guidelines
- HIG — Accessibility: https://developer.apple.com/design/human-interface-guidelines/accessibility
- HIG — Color: https://developer.apple.com/design/human-interface-guidelines/color
- HIG — Materials: https://developer.apple.com/design/human-interface-guidelines/materials
- HIG — Typography: https://developer.apple.com/design/human-interface-guidelines/typography
- HIG — Layout: https://developer.apple.com/design/human-interface-guidelines/layout
- SF Symbols: https://developer.apple.com/sf-symbols/
- Apple Design Resources: https://developer.apple.com/design/resources/
- Accessibility in SwiftUI: https://developer.apple.com/documentation/swiftui/accessibility-fundamentals

## Open questions

- Does a fixed-dark chrome treatment or a fully semantic light/dark chrome test better in bright
  outdoor use? Needs a real-device comparison in sunlight.
- What Dynamic Type cap keeps the live overlay spatially truthful without excluding users who need
  larger text? Needs testing at the accessibility sizes.
- Whether VoiceOver guidance should speak continuously or on-demand during composition — continuous
  speech may conflict with the photographer's attention.
