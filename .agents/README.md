# Shared Agent Skills

Canonical, vendor-neutral engineering skills for AI Photographer. **One copy of every skill**, used
by every coding agent that works in this repository.

## Layout

```
.agents/skills/<skill-name>/SKILL.md      ← canonical content
.agents/skills/<skill-name>/references/   ← focused reference files, loaded on demand
.claude/skills/<skill-name>               → symlink to ../../.agents/skills/<skill-name>
```

`.agents/skills/` follows the [Agent Skills](https://agentskills.io) open standard: a directory per
skill, a `SKILL.md` with YAML frontmatter (`name`, `description`), and optional `references/`,
`scripts/`, `assets/` subdirectories.

## How each agent finds them

| Agent | Mechanism | Adapter needed |
|---|---|---|
| **Codex CLI** | Scans `.agents/skills/` natively (repo root, cwd, and parents) | **None** |
| **Claude Code** | Scans `.claude/skills/`; each entry is a symlink to the canonical directory | 6 symlinks |
| Any other Agent Skills client | Point it at `.agents/skills/`, or add one symlink directory | Minimal |

There is deliberately **no `.codex/skills/`**. Codex scans `.agents/skills/` and `.codex/skills/` as
separate roots and does not deduplicate between them — a skill reachable from both is listed twice.
Verified against Codex CLI 0.144.6 on 2026-08-15.

Both agents follow symlinks and resolve them to the real path, so the canonical file is the one that
is read in every case. There is no synchronization step and nothing to keep in sync.

## The skills

| Skill | Load it when |
|---|---|
| `ios-camera` | AVFoundation capture, preview, frame delivery, photo capture, camera lifecycle |
| `ios-ui-design` | Any user-facing screen, overlay, control, or visual treatment |
| `camera-integration` | External/mirrorless cameras, capabilities, vendor adapters, camera bridge |
| `vision-spatial` | Vision, ARKit, CoreMotion, depth, coordinate transforms, spatial guidance |
| `photography-director` | AI planning, CompositionPlan, composition rules, providers, review/retake |
| `opensource-quality` | Architecture, boundaries, naming, testing, dependencies, secrets |

Load only what the task needs. `opensource-quality` pairs with essentially every code change; the
others are domain-specific. See `AGENTS.md` for the routing table.

## Editing a skill

Edit the file under `.agents/skills/`. Never edit through the `.claude/skills/` symlink path in a way
that would replace the link with a regular file — that is what starts a divergent copy.

Rules for skill content:

- Keep `SKILL.md` under ~500 lines. Move detail into `references/`.
- Frontmatter uses only Agent Skills spec fields — `name`, `description`, `license`,
  `compatibility`, `metadata`, `allowed-tools` — so skills stay portable across agents.
- `name` must be lowercase alphanumeric plus hyphens, and must match the directory name.
- `description` should say what the skill covers **and when to use it**; that text is how both agents
  decide whether to load it.
- References carry: purpose, relevant APIs, important behavior, limitations, pitfalls, official
  sources, last-verified date, open questions.
- Prefer primary sources. Label unverified claims honestly.

## Verifying the setup

```sh
.agents/verify-skills.sh
```

Checks frontmatter validity, name/directory agreement, symlink health and relativity, and that no
duplicate skill tree has appeared.

## Adding another agent

Create the directory that agent scans and symlink each skill into it, relative:

```sh
mkdir -p .someagent/skills
for s in .agents/skills/*/; do
  ln -s "../../.agents/skills/$(basename "$s")" ".someagent/skills/$(basename "$s")"
done
```

No skill content is copied, and no existing agent is affected.
