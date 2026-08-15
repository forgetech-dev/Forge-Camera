# AI Photographer — Project Goal

## 1. Project Vision

AI Photographer is an open-source, modular AI-assisted photography system that helps users make better photographic decisions before, during, and after capture.

The system should not merely score a photo or suggest generic composition rules. Its long-term goal is to act as an **AI photography director** that observes the current scene, understands the photographer's intent, proposes a target shot, and continuously guides the photographer, subject, and camera toward that target.

The core loop is:

```text
OBSERVE
   ↓
UNDERSTAND
   ↓
PLAN
   ↓
GUIDE
   ↓
CONTROL
   ↓
CAPTURE
   ↓
REVIEW
   ↓
REPLAN
```

The system should eventually coordinate three actors:

```text
Photographer
Subject
Camera
```

while keeping the architecture independent of any single camera brand, camera model, AI provider, backend service, or deployment environment.

---

## 2. Primary Product Goal

Build a photography assistant that can:

1. Analyze a live camera view.
2. Understand the scene and photographic intent.
3. Decide what a better target composition should look like.
4. Guide the photographer toward a better shooting position.
5. Guide a human subject toward a better position and pose.
6. Recommend focal length, camera height, camera angle, and framing.
7. Recommend and optionally apply camera settings.
8. Trigger autofocus and capture when supported.
9. Review captured images and recommend retakes.
10. Support both phone cameras and external mirrorless cameras through the same core pipeline.

The project should ultimately behave more like a closed-loop photography system than a static AI photo evaluator.

---

## 3. Capture Modes

The application should support two first-class capture modes.

### 3.1 Phone Camera Mode

Use the iPhone camera directly for:

- Live preview
- Scene analysis
- Composition guidance
- Photographer movement guidance
- Subject placement
- Pose guidance
- AR / motion tracking
- Exposure assistance
- Capture
- Post-shot review

This mode should work without any external camera.

### 3.2 External Camera Mode

Use an external camera as the primary image source.

Initial reference hardware:

```text
Sony A7C II / ILCE-7CM2
```

Initial reference lenses may include:

```text
Viltrox 35mm EVO
Viltrox 85mm EVO
```

These devices are **reference hardware only** and must not become architecture constraints.

Future camera support should include other models and brands where technically possible:

```text
Sony
Canon
Nikon
Fujifilm
Panasonic
Others
```

External Camera Mode should support, depending on camera capabilities:

- Live View
- Camera metadata
- Focal-length detection
- ISO control
- Shutter-speed control
- Aperture control
- Exposure compensation
- Autofocus
- Focus point control
- Shutter release
- Captured-image retrieval
- Computational photography workflows

---

## 4. AI Photography Director

The AI system should be responsible for **high-level photographic planning**, not low-level frame-by-frame control.

The AI Director should answer questions such as:

- Where should the subject be placed?
- What composition is appropriate for this scene?
- Should the camera be higher or lower?
- Should the photographer move left, right, forward, or backward?
- Which focal length would better serve the shot?
- How should the subject rotate or pose?
- Should the image emphasize the subject or the environment?
- What exposure priorities make sense for the intended result?

The AI Director should produce a structured target state rather than free-form instructions.

Example:

```json
{
  "intent": "environmental_portrait",
  "subject": {
    "targetX": 0.64,
    "targetY": 0.48,
    "targetHeight": 0.66,
    "bodyYaw": -20,
    "headYaw": 5
  },
  "scene": {
    "targetHorizon": 0.34
  },
  "camera": {
    "heightAdjustment": -0.15,
    "yawAdjustment": 7,
    "recommendedFocalLength": 35
  }
}
```

A deterministic local controller should then track the difference between the current state and this target state.

---

## 5. Real-Time Guidance Goal

The application should provide stable, actionable guidance instead of continuously generating new natural-language instructions.

Examples:

```text
Photographer:
← 40 cm
↓ 12 cm
↻ 6°

Subject:
→ 60 cm
Body left 20°

Camera:
35 mm
f/2.8
1/250
ISO Auto
```

When precise spatial measurement is unavailable, the application must degrade gracefully:

```text
Move left
Lower the camera slightly
Move the subject right
```

It must never invent false precision.

The guidance loop should run locally and substantially faster than the AI planning loop.

Target architecture:

```text
AI Planner
~0.2–2 Hz

Local Vision / Tracking
15–60 FPS

Guidance Rendering
30–60 FPS
```

---

## 6. Camera Automation Goal

Where supported by the connected camera and lens, the application should be able to read and control camera settings.

The user should have three control levels:

### Recommend

AI only recommends settings.

### Ask Before Apply

AI recommends settings and the user presses Apply.

This should be the default mode.

### Full Auto

The application automatically adjusts supported settings.

Potentially controlled settings include:

```text
ISO
Shutter Speed
Aperture
Exposure Compensation
White Balance
Autofocus
Focus Point
Shutter Release
```

The system must remain capability-driven. Unsupported controls must never be assumed.

---

## 7. Computational Photography Goal

The project should eventually support computational photography workflows similar in spirit to dedicated camera-assistant hardware, while keeping these features modular.

Potential modules:

```text
HDR / Exposure Bracketing
Focus Stacking
Long Exposure Stacking
Timelapse
Smart Timelapse
Panorama
Auto Capture
```

The AI should be able to recommend these modes when appropriate rather than requiring the user to manually select them in advance.

Example:

```text
High dynamic range detected
→ Recommend 3-shot exposure bracket
```

or:

```text
Foreground and background cannot both remain sharp
→ Recommend focus stack
```

---

## 8. Post-Shot Review Goal

The application should analyze captured photographs, ideally using the real captured image rather than only the lower-quality Live View frame.

Review should be able to detect issues such as:

```text
Horizon error
Subject placement
Distracting background objects
Objects intersecting the subject
Pose problems
Clipped highlights
Soft focus
Unwanted motion blur
Poor visual balance
```

The system should then recommend a retake when useful.

Example:

```text
Retake:

Photographer ← 35 cm
Subject → 20 cm
Camera ↓ 10 cm
```

This should close the loop between planning, capture, review, and replanning.

---

## 9. Modular Architecture Goal

Modularity is a core project requirement, but the project must avoid abstraction for abstraction's sake.

The main architecture rule is:

> Clear boundaries, shallow abstractions, explicit data flow, minimal dependencies.

The core domain must not depend on:

- Sony-specific protocols
- Canon-specific protocols
- A particular camera model
- Codex
- OpenAI
- A particular backend
- SwiftUI views
- A particular transport protocol

The project should instead rely on a small number of stable abstractions.

Core concepts should include:

```text
FrameSource
CameraAdapter
CameraCapabilities

SceneFrame
SceneState

DirectorProvider
CompositionPlan

GuidanceEngine
GuidanceState

CameraController
ExposureEngine
```

Adding a new camera brand should primarily require a new camera adapter and transport implementation.

Adding a new AI provider should primarily require a new DirectorProvider.

---

## 10. Backend Goal

The backend must be replaceable.

The initial development backend may use:

```text
macOS server
+
Codex CLI / Codex SDK
```

The application must not depend on Codex-specific behavior.

Future supported configurations may include:

### Local Mac Backend

```text
iPhone
→ Local Network
→ macOS Server
→ Codex
```

### Managed Cloud Backend

```text
App
→ Project Backend
→ AI Provider
```

### BYOK

```text
App
→ User-provided API key
→ AI Provider
```

### User-Hosted Backend

```text
App
→ Custom Endpoint
```

### Local Model

```text
App / Mac
→ Local Vision-Language Model
```

Changing the backend must not require changes to the Camera, Vision, Guidance, or UI layers.

---

## 11. Local-First Goal

Fast perception and tracking should run locally wherever practical.

Examples:

```text
Human detection
Pose detection
Face detection
Object tracking
Horizon detection
Motion tracking
ARKit pose
Depth
Optical flow
```

Cloud or remote AI should primarily handle high-level planning and deeper evaluation.

The system must not require continuous video upload to an AI service.

Preferred architecture:

```text
Live Video
   ↓
Local Vision
   ↓
Structured Scene State
   ↓
Occasional AI Planning
   ↓
Local Guidance Loop
```

This reduces latency, cost, bandwidth use, and privacy exposure.

---

## 12. Open-Source Engineering Goal

The project is intended to be open source.

Code quality, readability, maintainability, and contributor accessibility are therefore first-class requirements.

A new contributor should be able to understand:

- Where camera integrations live
- Where AI providers live
- Where scene analysis happens
- Where composition plans are defined
- Where guidance is calculated
- Where camera settings are applied
- Where UI presentation happens

without reading the entire repository.

The project must optimize for understandable code rather than clever code.

---

## 13. Code Quality Principles

### Readability First

Prefer explicit and readable implementations over highly compressed code.

### Shallow Structure

Avoid unnecessarily deep directory trees or excessive architecture layers.

### Small Public APIs

Each module should expose only what other modules actually need.

### Strong Naming

Prefer domain names such as:

```text
CompositionPlan
GuidanceState
ExposurePlan
CameraCapabilities
```

Avoid generic names such as:

```text
Manager
Helper
Utils
Processor
Thing
```

unless the name genuinely represents the role.

### Minimal Dependencies

Prefer Apple and standard-platform frameworks when they adequately solve the problem.

External dependencies must provide clear value.

### Simple Dependency Injection

Prefer initializer injection and small protocols.

Do not introduce large dependency-injection frameworks without demonstrated need.

### No Vendor Leakage

Sony-specific logic belongs in Sony modules.

Codex-specific logic belongs in the Codex provider.

Vendor details must not leak into the domain layer.

### No Premature Abstraction

Do not build factories, strategy layers, managers, registries, or generic frameworks merely for hypothetical future use.

Create an abstraction when there is a real or highly probable variation point.

---

## 14. Contributor Accessibility Goal

A developer without the reference Sony camera, paid AI API access, or a running Mac backend should still be able to clone and work on the project.

The repository should therefore provide:

```text
MockCameraAdapter
RecordedFrameSource
MockDirectorProvider
Sample / Recorded Sessions
```

A contributor should be able to run:

```bash
make build
make test
```

without physical camera hardware.

Hardware tests should remain separate from normal tests.

---

## 15. Headless Development Goal

The development workflow should support a headless macOS environment.

Normal development should be possible through:

```text
SSH
Git
Codex
Swift CLI tooling
xcodebuild
simctl
devicectl
```

The repository should eventually expose simple commands such as:

```bash
make build
make test
make device
make server
make archive
make testflight
```

Xcode GUI may still be used when helpful, but normal development, testing, and deployment should not depend on an active desktop session.

---

## 16. Privacy and Security Goal

The application should follow local-first privacy principles.

API keys and secrets must never be:

```text
Hardcoded
Committed to Git
Printed in logs
Stored in plaintext configuration
Uploaded through analytics
```

On iOS, secrets should use Keychain or an equivalent secure mechanism.

User photographs should not be stored or transmitted unnecessarily.

Remote AI requests should contain only the data required for the requested operation.

---

## 17. Graceful Degradation Goal

The system should remain useful when optional capabilities are unavailable.

Examples:

### No AI Backend

Still provide:

```text
Live View
Basic composition guides
Local tracking
Camera control
```

### No AR / Depth

Still provide directional guidance, but not fake metric distances.

### Camera Cannot Report Focal Length

Allow manual focal-length input.

### Camera Cannot Change Aperture

Show a manual adjustment request.

### Camera Cannot Provide Live View

Allow post-shot review if images can still be retrieved.

Individual feature failures must not unnecessarily disable the entire application.

---

## 18. Testing Goal

The project should be designed for automated testing from the beginning.

Required test categories:

### Unit Tests

```text
Guidance Engine
Exposure Engine
Camera capability handling
Schema validation
Director providers
```

### Integration Tests

```text
Frame → Vision → SceneState
SceneState → Director → CompositionPlan
CompositionPlan → Guidance
CameraController → MockCamera
```

### Replay Tests

Recorded sessions should allow deterministic regression testing.

### Hardware Tests

Real-camera tests should be isolated and explicitly invoked.

Normal CI must not require physical camera hardware.

---

## 19. Documentation Goal

The repository should maintain a small, clearly scoped documentation set.

```text
README.md
GOAL.md
REQUIREMENTS.md
PLAN.md
ARCHITECTURE.md
CONTRIBUTING.md
AGENTS.md
LICENSE
```

Each document has one purpose:

### GOAL.md

Why the project exists and what success looks like.

### REQUIREMENTS.md

What the system must do and the engineering constraints it must satisfy.

### PLAN.md

How the project will be implemented in phases.

### ARCHITECTURE.md

How the current implementation is structured.

### CONTRIBUTING.md

How humans should contribute.

### AGENTS.md

Rules and context for coding agents such as Codex.

Documentation should not duplicate the same information unnecessarily.

---

## 20. Initial Development Scope

The first practical version should prove the core product loop without attempting to implement every final feature.

A successful early version should be able to:

```text
iPhone Camera
   ↓
Capture Live Frame
   ↓
Analyze Scene
   ↓
Send Selected Frame to AI Director
   ↓
Receive Structured CompositionPlan
   ↓
Render Photographer / Subject Guidance
   ↓
Track Progress Locally
```

External camera integration should be developed behind the same abstractions.

The initial external-camera proof of concept should validate:

```text
A7C II connection
Live View
Read camera state
Read focal length
Set one or more exposure parameters
Trigger shutter
Retrieve preview image
```

before building advanced camera automation.

---

## 21. Long-Term Success Criteria

The project will be considered successful when the following experience is possible:

```text
1. User opens the app.
2. Selects Phone Camera or External Camera.
3. App understands the current scene.
4. AI proposes a target shot.
5. App guides the photographer toward the target viewpoint.
6. App guides the subject toward the desired position and pose.
7. App recommends or applies camera settings.
8. Guidance updates continuously as people and camera move.
9. App confirms when composition is ready.
10. App focuses and captures.
11. Captured image is reviewed.
12. If necessary, the system proposes a precise retake.
```

The user should feel that the system is helping create the photograph, not merely evaluating it afterward.

---

## 22. Non-Goals

The project should not attempt to become:

- A full Lightroom replacement
- A full Photoshop replacement
- A general photo-library manager
- A social network
- A cloud-storage platform
- A generic chatbot embedded in a camera screen
- A camera-brand-specific utility

Those features should not distract from the core photography-director loop.

---

## 23. Architectural Non-Goals

The project should specifically avoid:

```text
Over-engineered abstraction layers
Deep inheritance hierarchies
Vendor-specific logic in core modules
A giant global AppState
A giant CameraManager
A giant AIManager
Cloud AI on every video frame
UI directly controlling PTP commands
Vision code directly changing camera settings
Free-text AI responses used as application state
Hardware requirements for ordinary development
```

---

## 24. Guiding Principle

The project should remain:

> **Camera-independent, AI-provider-independent, backend-independent, modular, local-first, capability-driven, readable, and simple.**

The project should favor a clean implementation of the current real requirements over speculative frameworks for unknown future requirements.

The ultimate goal is simple:

> **Build an open-source AI photography system that decides what a better photograph should look like, then helps the photographer, subject, and camera reach that result in real time.**
