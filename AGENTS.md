# AGENTS.md

Instructions for coding agents working in this repository.

## Start here

1. **[`.agents/HANDOFF.md`](.agents/HANDOFF.md)** — what the last session did, what is in flight,
   which decisions are settled, and which traps have already cost someone time. Read this first;
   it is what makes switching between agents work.
2. [`goal.md`](goal.md) — project intent, architecture goals, and non-goals. The source of truth.
   Do not rewrite it.
3. [`plan.md`](plan.md) — phases, numbered requirements, and open decisions.

**Before you finish, update `.agents/HANDOFF.md`.** Refresh the current state, add a session log
entry naming which agent you are, and record any durable decision or trap. A handoff document
nobody maintains is worse than none, because the next agent will trust it.

## Use the shared project skills

Canonical skills live in [`.agents/skills/`](.agents/README.md). Codex discovers them natively.
Claude Code discovers the same directories through symlinks in `.claude/skills/`. There is one copy
of every skill — edit under `.agents/skills/`.

**Load only the skills the current task needs.** Loading all six wastes context and dilutes the
guidance that matters.

| Task | Load |
|---|---|
| Swift camera / capture change | `ios-camera`, `opensource-quality` |
| Camera HUD, overlay, any screen | `ios-ui-design`, `ios-camera` |
| Sony / external camera integration | `camera-integration`, `opensource-quality` (+ `ios-camera` if iOS transport is involved) |
| AR / photographer navigation, tracking, coordinates | `vision-spatial`, `ios-camera` |
| AI composition, planning, plan schema, review | `photography-director`, `opensource-quality` |
| Cross-module or architectural change | `opensource-quality` + only the affected domain skills |

`opensource-quality` applies to essentially every code change. The others are domain-specific.

## Working rules

- **Prefer primary technical sources.** Official Apple, Sony, OpenAI, and Anthropic documentation
  first; original research papers next; community discussion only for undocumented behavior, and
  labeled as unverified.
- **Keep architecture simple.** Clear boundaries, shallow abstractions, explicit data flow, minimal
  dependencies. Do not add an abstraction without a real variation point.
- **Do not silently bypass module boundaries.** The core domain imports `Foundation` only. Vendor
  logic stays in vendor modules. If a change appears to need a boundary crossed, raise it in the PR.
- **Run the appropriate build and tests after code changes.** Do not hand back unverified work.
- **Never fabricate precision.** Guidance without a valid metric estimate is directional only.
- **Never commit secrets, vendor SDKs, or licensed material.** See
  `.agents/skills/camera-integration/references/licensing.md`.
- **Label uncertain hardware claims**: confirmed / likely / requires hardware verification /
  unsupported. Desktop SDK support does not imply iOS support.

## Repository facts

- Swift 6, iOS 18+ / macOS 15+, Xcode 16.
- Ordinary development must work with **no camera hardware, no API key, and no network**.
  Hardware and external-service tests are isolated and explicitly invoked.
- `goal.md` §23 lists architectural anti-goals. Treat them as build-breaking.

## Verifying the skills setup

```sh
.agents/verify-skills.sh
```
