#!/bin/sh
# Enforce the module boundaries that the architecture depends on.
#
# Boundaries recorded only in a document erode. This is the difference between
# "we agreed on layering" and "layering is enforced".
#
# Usage: ./Tools/check-boundaries.sh   (exits non-zero on violation)

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CORE="$ROOT/Sources/ForgeCore"
FAIL=0

fail() { printf '  FAIL  %s\n' "$1"; FAIL=1; }
ok()   { printf '  ok    %s\n' "$1"; }

echo "Module boundaries"

# ---------------------------------------------------------------- core purity
# ForgeCore is the domain. It must not reach for a platform framework, because
# the moment it does, the domain stops being testable without a device.
if [ -d "$CORE" ]; then
  FORBIDDEN_IMPORTS="AVFoundation Vision ARKit CoreMotion CoreML SwiftUI UIKit AppKit CoreImage Metal ImageCaptureCore"
  violations=""
  for module in $FORBIDDEN_IMPORTS; do
    if grep -rlE "^[[:space:]]*(@[a-zA-Z]+[[:space:]]+)?import[[:space:]]+$module\b" "$CORE" 2>/dev/null | grep -q .; then
      violations="$violations $module"
    fi
  done
  if [ -n "$violations" ]; then
    fail "ForgeCore imports platform frameworks:$violations"
  else
    ok "ForgeCore imports Foundation only"
  fi
else
  ok "ForgeCore not present yet"
fi

# ------------------------------------------------------------ vendor leakage
# Vendor names belong in vendor modules. A core module that knows a camera's
# brand has already lost the capability-based design.
VENDORS="Sony Canon Nikon Fujifilm Panasonic Codex OpenAI Anthropic"
for vendor in $VENDORS; do
  # Vendor-owned directories are allowed to say the vendor's name.
  hits=$(grep -rlw "$vendor" "$ROOT/Sources" 2>/dev/null \
    | grep -v "/ForgeCamera$vendor/" \
    | grep -v "/ForgeDirector$vendor/" \
    || true)
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits" | while read -r file; do
      rel=$(printf '%s' "$file" | sed "s|$ROOT/||")
      fail "vendor name '$vendor' outside its module: $rel"
    done
    FAIL=1
  fi
done
[ "$FAIL" -eq 0 ] && ok "no vendor names outside vendor modules"

# --------------------------------------------------------------- test support
# ForgeTestSupport exists to serve tests. If production code depends on it, the
# mocks have quietly become the implementation.
if [ -d "$ROOT/Sources" ]; then
  bad=$(grep -rl "import ForgeTestSupport" "$ROOT/Sources" 2>/dev/null \
    | grep -v "/ForgeTestSupport/" || true)
  if [ -n "$bad" ]; then
    printf '%s\n' "$bad" | while read -r file; do
      rel=$(printf '%s' "$file" | sed "s|$ROOT/||")
      fail "production code imports ForgeTestSupport: $rel"
    done
    FAIL=1
  else
    ok "ForgeTestSupport is used by tests only"
  fi
fi

# ------------------------------------------------------- free-text as state
# The one prose field a plan carries is display-only. Branching on it turns an
# AI's free text into application state, which the architecture forbids.
if [ -d "$ROOT/Sources" ]; then
  # Allow for optional chaining and force-unwrap between the property and the
  # call: `rationale?.contains`, `rationale!.hasPrefix`, `rationale.contains`.
  bad=$(grep -rnE 'rationale[?!]?[[:space:]]*(\.contains|\.hasPrefix|\.hasSuffix|\.range\(|==[^=])' "$ROOT/Sources" 2>/dev/null || true)
  if [ -n "$bad" ]; then
    printf '%s\n' "$bad" | while read -r line; do
      fail "branching on plan rationale (display-only): $line"
    done
    FAIL=1
  else
    ok "no logic branches on plan rationale"
  fi
fi

echo ""
if [ "$FAIL" -eq 0 ]; then
  echo "boundaries: clean"
else
  echo "boundaries: VIOLATIONS FOUND"
fi
exit "$FAIL"
