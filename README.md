# AI Photographer

An open-source AI photography system that decides what a better photograph should look like, then
helps the photographer, subject, and camera reach that result in real time.

Rather than scoring a picture after the fact, it observes the scene, proposes a target shot, and
guides you toward it while you compose:

```
OBSERVE → UNDERSTAND → PLAN → GUIDE → CONTROL → CAPTURE → REVIEW → REPLAN
```

Two capture modes share one pipeline: the iPhone camera on its own, and an external mirrorless
camera (reference hardware: Sony A7C II) behind the same abstractions.

Read **[goal.md](goal.md)** for the full vision, architecture goals, and non-goals.

## Status

**Pre-implementation.** The repository currently contains project direction and the shared
engineering skills that coding agents use. There is no application code yet.

| | |
|---|---|
| [`goal.md`](goal.md) | Why the project exists and what success looks like. Source of truth. |
| [`plan.md`](plan.md) | Phased implementation plan, requirements, and engineering guidelines. |
| [`.agents/`](.agents/README.md) | Shared engineering skills for coding agents. |
| [`AGENTS.md`](AGENTS.md) | How coding agents should work in this repo. |

## Design principles

Camera-independent, AI-provider-independent, backend-independent, modular, local-first,
capability-driven, readable, and simple.

Fast perception runs **on device**; a remote AI planner is consulted occasionally, not per frame. No
continuous video is ever uploaded. When a capability is missing — no AI backend, no depth, no camera
control — the app degrades honestly rather than breaking, and it never invents precision it cannot
measure.

## Development

Requires macOS with **Xcode 16** (Swift 6, iOS 18 SDK).

Once code lands, the contributor promise is that ordinary development needs **no camera hardware, no
API key, and no paid AI backend**:

```sh
make build
make test
```

Hardware tests and external-service tests are isolated and explicitly invoked. Mock adapters,
recorded sessions, and a deterministic offline director stand in for everything else.

## Working with coding agents

This project is developed with both OpenAI Codex and Anthropic Claude Code. They share one canonical
set of engineering skills in [`.agents/skills/`](.agents/README.md) — Codex reads that directory
natively, and Claude Code reaches the same files through symlinks in `.claude/skills/`. There is one
copy of every skill and nothing to keep in sync.

```sh
.agents/verify-skills.sh    # validate the skill setup
```

Start at [`AGENTS.md`](AGENTS.md) for the skill-routing table and working rules.

## License

Intended: Apache-2.0. The `LICENSE` file has not been added yet.

Vendor camera SDKs are **not** redistributable and are never committed here — see
[`.agents/skills/camera-integration/references/licensing.md`](.agents/skills/camera-integration/references/licensing.md).

"Sony", "Alpha", and "Viltrox" are trademarks of their respective owners, referenced here only to
describe hardware compatibility.
