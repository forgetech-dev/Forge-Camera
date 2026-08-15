#!/bin/sh
# Verify the shared skill setup: canonical skills are valid, and every agent
# adapter points at them instead of holding a copy.
#
# Usage: .agents/verify-skills.sh
# Exits non-zero on any failure.

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CANON="$ROOT/.agents/skills"
FAIL=0

fail() { printf '  FAIL  %s\n' "$1"; FAIL=1; }
ok()   { printf '  ok    %s\n' "$1"; }

echo "Canonical skills: $CANON"
echo

# ---------------------------------------------------------------- canonical
echo "Skill validity"
COUNT=0
for dir in "$CANON"/*/; do
  [ -d "$dir" ] || continue
  name=$(basename "$dir")
  COUNT=$((COUNT + 1))
  md="$dir/SKILL.md"

  [ -f "$md" ] || { fail "$name: no SKILL.md"; continue; }

  # Frontmatter must open on line 1 and close.
  [ "$(head -1 "$md")" = "---" ] || { fail "$name: SKILL.md must start with '---'"; continue; }
  awk 'NR>1 && /^---[[:space:]]*$/ {found=1; exit} END {exit !found}' "$md" \
    || { fail "$name: frontmatter not closed"; continue; }

  fm=$(awk 'NR>1 && /^---[[:space:]]*$/ {exit} NR>1' "$md")
  fmname=$(printf '%s\n' "$fm" | sed -n 's/^name:[[:space:]]*//p' | head -1)
  fmdesc=$(printf '%s\n' "$fm" | sed -n 's/^description:[[:space:]]*//p' | head -1)

  [ -n "$fmname" ] || fail "$name: frontmatter 'name' missing or empty"
  [ -n "$fmdesc" ] || fail "$name: frontmatter 'description' missing or empty"

  # Agent Skills spec: name must equal the directory name.
  [ "$fmname" = "$name" ] || fail "$name: frontmatter name '$fmname' != directory name"

  # Agent Skills spec: lowercase alnum + hyphens, no leading/trailing/double hyphen, <=64.
  printf '%s' "$fmname" | grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$' \
    || fail "$name: name must be lowercase alphanumeric with single hyphens"
  [ "${#fmname}" -le 64 ] || fail "$name: name longer than 64 characters"

  # description <= 1024 chars, and long enough to route on.
  [ "${#fmdesc}" -le 1024 ] || fail "$name: description longer than 1024 characters"
  [ "${#fmdesc}" -ge 40 ]   || fail "$name: description too short to route on"

  # Only Agent Skills spec fields, so skills stay portable across agents.
  printf '%s\n' "$fm" | grep -E '^[a-zA-Z][a-zA-Z0-9_-]*:' | sed 's/:.*//' | while read -r key; do
    case "$key" in
      name|description|license|compatibility|metadata|allowed-tools) ;;
      *) printf '  WARN  %s: non-spec frontmatter key "%s" (portable agents may reject it)\n' "$name" "$key" ;;
    esac
  done

  # Keep SKILL.md small enough to load cheaply.
  lines=$(wc -l < "$md" | tr -d ' ')
  [ "$lines" -le 500 ] || printf '  WARN  %s: SKILL.md is %s lines (recommended max 500)\n' "$name" "$lines"

  [ "$FAIL" -eq 0 ] && ok "$name ($lines lines)"
done
[ "$COUNT" -gt 0 ] || fail "no skills found in $CANON"
echo

# ------------------------------------------------------------------ adapters
echo "Claude Code adapter (.claude/skills)"
for dir in "$CANON"/*/; do
  name=$(basename "$dir")
  link="$ROOT/.claude/skills/$name"

  [ -L "$link" ] || { fail "$name: .claude/skills/$name is not a symlink"; continue; }

  target=$(readlink "$link")
  case "$target" in
    /*) fail "$name: symlink is absolute ($target); must be relative for portability"; continue ;;
  esac

  [ -f "$link/SKILL.md" ] || { fail "$name: symlink does not resolve to a SKILL.md"; continue; }

  # The link must resolve to the canonical directory, not a copy.
  real=$(cd "$link" && pwd -P)
  want=$(cd "$dir" && pwd -P)
  [ "$real" = "$want" ] || { fail "$name: resolves to $real, expected $want"; continue; }

  ok "$name -> $target"
done
echo

# --------------------------------------------------------------- duplication
echo "No duplicate skill trees"
# Codex scans .agents/skills and .codex/skills as separate roots and does not
# deduplicate between them, so .codex/skills must not exist.
if [ -e "$ROOT/.codex/skills" ]; then
  fail ".codex/skills exists; Codex would list every skill twice. Remove it."
else
  ok ".codex/skills absent (Codex reads .agents/skills natively)"
fi

dupes=$(find "$ROOT" -name SKILL.md -not -path "$ROOT/.agents/*" -not -path "*/node_modules/*" 2>/dev/null)
if [ -n "$dupes" ]; then
  printf '%s\n' "$dupes" | while read -r d; do fail "skill content outside .agents: $d"; done
else
  ok "all SKILL.md content lives under .agents/skills"
fi
echo

if [ "$FAIL" -eq 0 ]; then
  echo "PASS  $COUNT skills, one canonical copy each."
else
  echo "FAILED"
fi
exit "$FAIL"
