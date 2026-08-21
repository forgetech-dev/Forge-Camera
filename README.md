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

**Phase 1 is complete and the Phase 2 phone-camera vertical slice runs on a physical iPhone.** The
Foundation-only domain, capture and Vision pipeline, composition guidance, deterministic director,
tested preview geometry, and 182 hardware-free tests are working. A loopback-only Mac development
server now accepts one image, invokes the installed Codex CLI, and returns a validated composition
plan; phone-to-Mac LAN networking is not connected yet.

| | |
|---|---|
| [`goal.md`](goal.md) | Why the project exists and what success looks like. Source of truth. |
| [`plan.md`](plan.md) | Phased implementation plan, requirements, and engineering guidelines. |
| [`.agents/`](.agents/README.md) | Shared engineering skills for coding agents. |
| [`AGENTS.md`](AGENTS.md) | How coding agents should work in this repo. |
| [`LICENSE`](LICENSE) | Apache-2.0. |

## Design principles

Camera-independent, AI-provider-independent, backend-independent, modular, local-first,
capability-driven, readable, and simple.

Fast perception runs **on device**; a remote AI planner is consulted occasionally, not per frame. No
continuous video is ever uploaded. When a capability is missing — no AI backend, no depth, no camera
control — the app degrades honestly rather than breaking, and it never invents precision it cannot
measure.

## Development

Requires macOS with **Xcode 16** (Swift 6, iOS 18 SDK).

Ordinary development needs **no camera hardware, no API key, and no paid AI backend**:

```sh
make check
```

Hardware tests and external-service tests are isolated and explicitly invoked. Mock adapters,
recorded sessions, and a deterministic offline director stand in for everything else.

To explicitly run the development-only real-AI spike, first sign in with the installed Codex CLI,
then provide one non-sensitive JPEG or PNG. The provider downsizes it to a maximum 1024-pixel edge,
re-encodes it without source metadata, runs an ephemeral read-only `codex exec`, and validates the
structured result. This command uses an external service and never runs in ordinary tests or CI:

```sh
make codex-spike IMAGE=/path/to/image.jpg
```

To exercise the same provider through the development HTTP boundary, start the server in one
terminal, then upload an image from another. The current server deliberately binds only to
`127.0.0.1`; it is not reachable from an iPhone or another computer and does not need an application
credential. The plan route invokes the external Codex service; the health route does not.

```sh
make server

curl http://127.0.0.1:8765/health
curl --form image=@/path/to/image.jpg http://127.0.0.1:8765/v1/plan
```

LAN access will be added separately with an explicit development pairing token before the listener
is allowed to leave the loopback interface.

The iOS project is generated rather than committed. Install XcodeGen 2.46.0, then run:

```sh
make project    # regenerate Forge.xcodeproj from project.yml
make app        # unsigned compile-only iOS simulator build
```

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

[Apache-2.0](LICENSE). Chosen over MIT for its express patent grant — this project moves into
computational photography and camera control, which are patent-dense areas, and Apache-2.0 passes a
patent license from every contributor through to users.

Contributions are accepted under the same license, per Apache-2.0 §5. Attribution and third-party
notices are recorded in [`NOTICE`](NOTICE).

Vendor camera SDKs are **not** redistributable and are never committed here — see
[`.agents/skills/camera-integration/references/licensing.md`](.agents/skills/camera-integration/references/licensing.md).

"Sony", "Alpha", and "Viltrox" are trademarks of their respective owners, referenced here only to
describe hardware compatibility.
