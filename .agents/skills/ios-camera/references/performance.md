# Camera Performance, Latency, and Thermal — Project Reference

**Purpose.** How to make performance claims in this project honest, and what to do when the device
gets hot. Rule: a latency number that was not measured does not go in a commit message, a comment,
or a code review.

**Last verified:** 2026-08-15.

---

## Latency budgets

These are the project's working targets. They are budgets to measure against, not guarantees.

| Stage | Budget | Notes |
|---|---|---|
| Frame acquisition → delegate callback | AVFoundation-owned | Not ours to optimize; measure to know the floor. |
| Frame → `SceneState` (local analysis) | ≤ 33 ms p95 | One frame at 30 FPS. Exceeding it means dropping frames, which is allowed. |
| `SceneState` → `GuidanceState` | ≤ 5 ms p95 | Pure computation, no I/O. If this is slow, the engine is doing something it shouldn't. |
| `GuidanceState` → rendered overlay | one display frame | Overlay updates must not trigger layout of the whole view tree. |
| Plan request → validated `CompositionPlan` | ≤ 3 s p95 | Off the critical path entirely; guidance runs on the latched plan meanwhile. |

The end-to-end number the user actually feels is *frame → overlay*. Measure that, not the sum of
optimistic component numbers.

## How to measure

**Signposts, not print statements.** Use `OSSignposter` with a dedicated
`OSLog(subsystem:category: .pointsOfInterest)` and view in Instruments. Signposts survive in release
builds, cost almost nothing, and give real distributions instead of one lucky sample.

```swift
let signposter = OSSignposter(subsystem: "dev.forge.photographer", category: "pipeline")
let state = signposter.withIntervalSignpost("analyze") { analyzer.analyze(frame) }
```

**Instruments templates that matter here:** Time Profiler (where the CPU goes), Animation Hitches
(dropped preview/overlay frames), Metal System Trace if a Metal overlay path is added, and the
Thermal State track alongside them.

**Frame accounting.** Count three separate things and log them together: frames delivered, frames
analyzed, frames dropped. A pipeline that "runs at 30 FPS" while analyzing 6 of them is a different
system from one analyzing all 30, and only the counters distinguish them.

**Percentiles, not averages.** p50 hides the stalls that users notice. Track p95.

**Device, not simulator.** The simulator has no real camera pipeline, no Neural Engine behavior, and
no thermal model. Performance numbers from the simulator are meaningless. Ordinary correctness tests
still run fine there — see `opensource-quality`.

## Where the time actually goes

In this class of pipeline, in rough order of typical cost:

1. **Vision requests** — body pose is far more expensive than face or rectangle detection. Cost
   scales with input resolution: downscale before analysis rather than handing Vision a 4K buffer.
2. **Pixel format conversion** — an unexpected conversion (e.g. because the requested format was not
   set explicitly) can silently dominate. Verify the format actually delivered.
3. **CPU-side buffer copies** — every `CVPixelBufferLockBaseAddress` + memcpy is real. Prefer
   staying on GPU/Neural Engine paths.
4. **Main-thread contention** — SwiftUI re-rendering a complex view tree per frame will hitch the
   preview even though the camera is fine. Overlay state should be a small value type, and only the
   overlay view observes it.
5. **JPEG/HEIC encoding** — never in the realtime path. Only at the AI-request boundary and at
   capture.

## Thermal behavior

Sustained capture + per-frame Vision + ARKit is one of the heaviest workloads an app can run.
Thermal throttling is not a failure mode to prevent; it is a state to handle.

Observe `ProcessInfo.processInfo.thermalStateDidChangeNotification` and read `thermalState`:

| State | Meaning | Project response |
|---|---|---|
| `.nominal` | Normal | Full analysis rate. |
| `.fair` | Slightly elevated | Full rate; start counting. |
| `.serious` | Throttling active | Halve analysis rate. Preview stays at full rate. Reduce ARKit usage if running. |
| `.critical` | Severe | Minimum analysis. Surface the state to the user. Keep preview and capture alive. |

Two rules:

- **Preview and shutter are the last things to degrade.** A user can live with less frequent
  guidance; they cannot live with a camera that will not take the picture.
- **Degradation is visible.** `goal.md` §17 requires graceful degradation, and the corollary is that
  the user is told. A silently downgraded experience reads as a broken app.

Also watch `ProcessInfo.isLowPowerModeEnabled` — it should reduce the analysis rate for the same
reasons, and it is a much cheaper signal to test against.

## Pitfalls

- Benchmarking with the debugger attached — Swift runtime checks and debug builds distort
  everything. Profile release builds.
- Measuring one frame and calling it a p95.
- Optimizing analysis while the real cost is a main-thread SwiftUI update.
- Treating a thermal-throttled measurement as the baseline, or vice versa. Record `thermalState`
  alongside every performance number.
- Adding a "performance improvement" with no before/after measurement. In this project that is not a
  performance change, it is an untested refactor.

## Official sources

- `OSSignposter`: https://developer.apple.com/documentation/os/ossignposter
- Instruments / performance: https://developer.apple.com/documentation/xcode/improving-your-app-s-performance
- `ProcessInfo.ThermalState`: https://developer.apple.com/documentation/foundation/processinfo/thermalstate
- WWDC "Ultimate application performance survival guide" and Instruments sessions:
  https://developer.apple.com/videos/

## Open questions

- Measured frame → `SceneState` time for `DetectHumanBodyPoseRequest` at 1080p and at a downscaled
  resolution on the target device. **Requires hardware verification.** Determines the analysis
  resolution and whether the 33 ms budget is realistic.
- Sustained-capture time to reach `.serious` on the target device with ARKit running, which sets how
  aggressive the default degradation ladder needs to be.
