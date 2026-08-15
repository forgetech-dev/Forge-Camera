# Research Grounding — Capture-Time Photography Guidance

**Purpose.** Published work directly relevant to what this project is building: what each contributes,
what to borrow, and what not to assume. Prior art matters here because "AI tells you how to take the
photo" is an active research area, not an unexplored one.

**Last verified:** 2026-08-15. Citations are to arXiv listings; verify version and venue before
citing formally.

---

## ShutterMuse: Capture-Time Photography Guidance with MLLMs

arXiv:2606.25763 · https://arxiv.org/abs/2606.25763 · code: https://github.com/lijayuTnT/ShutterMuse

The closest published analogue to this project's Director. A multimodal LLM for capture-time
guidance, with two complementary tasks: **photographer-side** composition decision and refinement,
and **subject-side** scene-conditioned pose recommendation. Ships `CaptureGuide-Bench` and
`CaptureGuide-Dataset` (~130K samples with textual rationales and structured visual annotations).

**Why it matters here:** it validates the core product hypothesis and, importantly, the
photographer/subject split that `goal.md` §1 describes as three actors. The structured-annotation
approach aligns with this project's insistence on structured plans over prose.

**What to take:** the two-sided task decomposition; the benchmark structure as a model for our own
evaluation; the pairing of a structured output with a human-readable rationale — which is exactly the
`rationale`-is-display-only pattern in [plan-schema.md](plan-schema.md).

**What not to assume:** research inference cost and latency are not product cost and latency. This
project's constraint — a *slow* planner behind a *fast* local loop — is an engineering requirement
that a research system does not have to satisfy.

## Towards Smart Point-and-Shoot Photography

arXiv:2505.03638 · https://arxiv.org/abs/2505.03638

A smart point-and-shoot (SPAS) system that guides users to adjust **camera pose** live in the scene.
Built on a dataset of ~320K images with camera-pose information across ~4000 scenes, and a CLIP-based
Composition Quality Assessment (CCQA) model used to assign pseudo-labels.

**Why it matters here:** it is specifically about *live camera-pose guidance*, which is the
photographer-movement half of this product, and it demonstrates learned composition-quality scoring
as a driver for guidance.

**What to take:** the idea that composition quality can be scored continuously and used as a gradient
toward a better viewpoint — useful for `HeuristicDirector` and for evaluating whether guidance
actually improves anything.

**What not to assume:** pseudo-labelled aesthetic scores encode dataset preferences. A learned "good
composition" signal is a strong default, not ground truth, and must remain overridable — consistent
with the rules-are-defaults principle in [composition.md](composition.md).

## Before the Shutter: Aesthetic and Actionable Portrait Photography Planning in 3D Scenes

arXiv:2605.30318 · https://arxiv.org/abs/2605.30318

Given a static 3D scene, a human subject, and a prompt specifying desired portrait style, it generates
candidate **portrait plans** — each specifying subject pose and placement, camera configuration,
controllable lighting, and exposure — that are both visually compelling and physically actionable.
The authors call this *3D aesthetic portrait planning*.

**Why it matters here:** the strongest prior art for the *plan* abstraction itself. It independently
arrives at a structured, multi-part, physically actionable plan covering subject, camera, and
exposure — very close to `CompositionPlan`. The emphasis on **actionable** plans matches this
project's requirement that a plan reduce to concrete guidance.

**What to take:** the plan decomposition, and the discipline of generating *candidate* plans that are
checked for physical actionability before being offered.

**What not to assume:** it operates on a known 3D scene. This project has a live 2D view and, at best,
partial depth. Anything depending on full 3D scene knowledge does not transfer directly.

## CameraBench / Towards Understanding Camera Motions in Any Video

arXiv:2504.15376 · https://arxiv.org/abs/2504.15376 · project:
https://linzhiqiu.github.io/papers/camerabench/ · code: https://github.com/sy77777en/CameraBench
(NeurIPS 2025 Spotlight)

~3,000 expert-annotated internet videos, with a **taxonomy of camera-motion primitives developed with
cinematographers**. Finds that structure-from-motion models miss semantic primitives that depend on
scene content, while video-language models miss geometric primitives requiring precise trajectory
estimation.

**Why it matters here — the single most directly applicable finding:** their human study reports that
novices confuse **zoom-in (a change of intrinsics)** with **translating forward (a change of
extrinsics)**, and that training fixes it. That distinction is precisely the rotate-vs-dolly-vs-zoom
decision in `vision-spatial` and the guidance-priority ordering the engine implements. If expert
humans need training to tell these apart, our *interface* must make them unmistakable — which is why
the overlay spec requires a distinct glyph for dolly rather than an in-plane arrow.

**What to take:** the motion taxonomy as vocabulary for `GuidanceAxis`; the SfM-vs-VLM split as
evidence for this project's architecture, where geometry is computed locally and semantics come from
the MLLM.

## Cross-cutting lessons

1. **The photographer/subject split is real and independently arrived at.** Two of these works treat
   subject-side guidance as a distinct task. `GuidanceActor` is well-founded.
2. **Structured plans beat prose**, in the literature as in this codebase.
3. **Geometry local, semantics learned.** CameraBench's finding is the clearest external support for
   this project's core architectural split.
4. **Evaluation is the hard part.** Every one of these papers ships a benchmark, because "did the
   guidance help?" has no obvious metric. Recorded sessions plus golden-file guidance tests
   (`opensource-quality`) are this project's minimum viable equivalent, and they measure
   *consistency*, not *quality*. Measuring quality remains open.

## How to use this in the project

- Cite as prior art and vocabulary, not as specification.
- Never copy datasets, model weights, or code into this repository without checking each project's
  license individually. An arXiv paper's availability says nothing about its code or data license.
- When implementing something a paper describes, write it from the described idea, not from their
  code, unless the license clearly permits reuse and the dependency is worth it.

## Open questions

- Is there a usable metric for "did guidance improve the photograph?" beyond consistency testing?
- Would a CCQA-style learned composition score be a better `HeuristicDirector` than explicit rules —
  and is the on-device cost acceptable?
- Do any of these works publish a taxonomy of *subject-side* pose guidance directly reusable as
  `poseHint` values?
