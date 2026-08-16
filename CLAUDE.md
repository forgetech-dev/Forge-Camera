# CLAUDE.md

Claude Code shares this repository's engineering guidance with Codex. **Read
[`AGENTS.md`](AGENTS.md)** — it holds the skill-routing table and the working rules, and it applies
here unchanged.

Start with [`.agents/HANDOFF.md`](.agents/HANDOFF.md) for what the last session left behind, and
update it before you finish.

Claude Code specifics:

- Project skills resolve from `.claude/skills/`, where each entry is a symlink to the canonical skill
  in `.agents/skills/`. Claude Code follows symlinks and reads `SKILL.md` from the target, so the
  canonical file is what loads. Invoke one directly with `/<skill-name>` or let it load
  automatically when a task matches its description.
- Edit skills at `.agents/skills/<name>/`, never through the symlink in a way that replaces the link
  with a regular file.
- If a newly added skill does not appear, restart the session — Claude Code watches skill directories
  that existed at startup, but a newly created top-level skills directory needs a restart.

Everything else — project intent (`goal.md`), skill routing, boundaries, testing, and source
priority — is in `AGENTS.md` and the skills themselves.
