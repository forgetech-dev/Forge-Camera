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
FRAME="$ROOT/Sources/ForgeFrame"
CAPTURE="$ROOT/Sources/ForgeCapture"
TEST_SUPPORT="$ROOT/Sources/ForgeTestSupport"
IMPORT_FIXTURES="$ROOT/Fixtures/boundaries/import-syntax.swift"
FAIL=0

fail() { printf '  FAIL  %s\n' "$1"; FAIL=1; }
ok()   { printf '  ok    %s\n' "$1"; }

imports_in() {
  if ! IMPORT_SCAN_OUTPUT=$(find "$1" -type f -name '*.swift' -exec awk '
    function is_import_prefix(value) {
      return value ~ /^@[_a-zA-Z][_a-zA-Z0-9]*/ ||
        value == "public" || value == "package" || value == "internal" ||
        value == "private" || value == "fileprivate" || value == "open"
    }
    function emit_import(statement, count, position) {
      sub(/^[[:space:]]*/, "", statement)
      sub(/[[:space:]]*$/, "", statement)
      if (statement == "") return
      count = split(statement, token, /[[:space:]]+/)
      position = 1
      while (position <= count && is_import_prefix(token[position])) position++
      if (token[position] != "import") return
      position++
      if (token[position] ~ /^(typealias|struct|class|enum|protocol|let|var|func)$/) position++
      split(token[position], component, ".")
      if (component[1] ~ /^[_a-zA-Z][_a-zA-Z0-9]*$/) print component[1]
    }
    {
      remaining = $0
      uncommented = ""
      while (length(remaining) > 0) {
        if (block_comment_depth > 0) {
          open_at = index(remaining, "/*")
          close_at = index(remaining, "*/")
          if (open_at > 0 && (close_at == 0 || open_at < close_at)) {
            block_comment_depth++
            remaining = substr(remaining, open_at + 2)
          } else if (close_at > 0) {
            block_comment_depth--
            remaining = substr(remaining, close_at + 2)
          } else {
            remaining = ""
          }
        } else {
          open_at = index(remaining, "/*")
          if (open_at == 0) {
            uncommented = uncommented remaining
            remaining = ""
          } else {
            uncommented = uncommented substr(remaining, 1, open_at - 1)
            remaining = substr(remaining, open_at + 2)
            block_comment_depth = 1
          }
        }
      }
      sub(/\/\/.*/, "", uncommented)
      statement_count = split(uncommented, statements, ";")
      for (statement_index = 1; statement_index <= statement_count; statement_index++) {
        emit_import(statements[statement_index])
      }
    }
  ' {} +); then
    printf '%s\n' __IMPORT_SCAN_FAILED__
    return
  fi
  # LC_ALL=C so the ordering is byte order everywhere. Without it the collation of
  # mixed-case module names depends on the runner's locale, and a set comparison
  # against a fixed list becomes environment-dependent.
  printf '%s\n' "$IMPORT_SCAN_OUTPUT" | LC_ALL=C sort -u
}

echo "Module boundaries"

# ------------------------------------------------------------ scanner sanity
# These legal Swift spellings have each bypassed a simpler regex in the past.
# The guard fails closed if its own parser stops recognizing any of them.
EXPECTED_FIXTURE_IMPORTS='ARKit
AppKit
CoreML
CoreMedia
CoreVideo
Foundation
Metal
SwiftUI
UIKit
Vision'
actual_fixture_imports=$(imports_in "$(dirname "$IMPORT_FIXTURES")")
if [ "$actual_fixture_imports" = "$EXPECTED_FIXTURE_IMPORTS" ]; then
  ok "import scanner recognizes guarded Swift syntax"
else
  fail "import scanner regression in Fixtures/boundaries/import-syntax.swift"
  # A guard that fails without saying what it saw cannot be diagnosed on a machine
  # you do not have. This one differed between a developer laptop and CI and cost
  # three rounds of guessing before anyone could see the actual output.
  printf '        fixture file: %s\n' "$IMPORT_FIXTURES"
  if [ -r "$IMPORT_FIXTURES" ]; then
    printf '        readable:     yes (%s bytes)\n' "$(wc -c < "$IMPORT_FIXTURES" | tr -d ' ')"
  else
    printf '        readable:     NO — the scanner had nothing to read\n'
  fi
  printf '        awk:          %s\n' "$(command -v awk)"
  printf '        expected:     %s\n' "$(printf '%s' "$EXPECTED_FIXTURE_IMPORTS" | tr '\n' ' ')"
  printf '        actual:       %s\n' "$(printf '%s' "$actual_fixture_imports" | tr '\n' ' ')"
fi

# ---------------------------------------------------------------- core purity
# ForgeCore is the domain. It must not reach for a platform framework, because
# the moment it does, the domain stops being testable without a device.
if [ -d "$CORE" ]; then
  violations=""
  for module in $(imports_in "$CORE"); do
    case "$module" in
      Foundation) ;;
      *) violations="$violations $module" ;;
    esac
  done
  if [ -n "$violations" ]; then
    fail "ForgeCore imports modules other than Foundation:$violations"
  else
    ok "ForgeCore imports Foundation only"
  fi
else
  ok "ForgeCore not present yet"
fi

# ------------------------------------------------------------- frame boundary
# CoreVideo's non-Sendable buffer is isolated in one narrow ownership module shared
# by capture and analysis. It has no camera-session, Vision, UI, or network behavior.
if [ -d "$FRAME" ]; then
  violations=""
  for module in $(imports_in "$FRAME"); do
    case "$module" in
      CoreVideo|Foundation) ;;
      *) violations="$violations $module" ;;
    esac
  done
  if [ -n "$violations" ]; then
    fail "ForgeFrame imports modules outside CoreVideo/Foundation:$violations"
  else
    ok "ForgeFrame stays inside the immutable frame boundary"
  fi
fi

# ----------------------------------------------------------- capture isolation
# Phone capture may use the native camera/media stack and iOS lifecycle signals,
# but it must not analyze frames, render UI, perform network I/O, or know vendors.
if [ -d "$CAPTURE" ]; then
  violations=""
  for module in $(imports_in "$CAPTURE"); do
    case "$module" in
      AVFoundation|CoreMedia|CoreVideo|ForgeCore|ForgeFrame|Foundation|OSLog|UIKit) ;;
      *) violations="$violations $module" ;;
    esac
  done
  if [ -n "$violations" ]; then
    fail "ForgeCapture imports modules outside its boundary:$violations"
  else
    ok "ForgeCapture stays inside the native capture boundary"
  fi
fi

# --------------------------------------------------------- test-support purity
# Recorded sources and mocks stay portable: ordinary tests cannot inherit a
# camera-framework or production-module dependency through their fixtures.
if [ -d "$TEST_SUPPORT" ]; then
  violations=""
  for module in $(imports_in "$TEST_SUPPORT"); do
    case "$module" in
      ForgeCore|Foundation) ;;
      *) violations="$violations $module" ;;
    esac
  done
  if [ -n "$violations" ]; then
    fail "ForgeTestSupport imports modules outside ForgeCore/Foundation:$violations"
  else
    ok "ForgeTestSupport remains hardware-free"
  fi
fi

# ------------------------------------------------------------ vendor leakage
# Vendor names belong in vendor modules. A core module that knows a camera's
# brand has already lost the capability-based design.
VENDORS="Sony Canon Nikon Fujifilm Panasonic Codex OpenAI Anthropic"
VENDOR_FAIL=0
for vendor in $VENDORS; do
  # Vendor-owned directories are allowed to say the vendor's name.
  hits=$(grep -rlF "$vendor" "$ROOT/Sources" "$ROOT/App" 2>/dev/null \
    | grep -v "/ForgeCamera$vendor/" \
    | grep -v "/ForgeDirector$vendor/" \
    || true)
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits" | while read -r file; do
      rel=$(printf '%s' "$file" | sed "s|$ROOT/||")
      fail "vendor name '$vendor' outside its module: $rel"
    done
    FAIL=1
    VENDOR_FAIL=1
  fi
done
[ "$VENDOR_FAIL" -eq 0 ] && ok "no vendor names outside vendor modules"

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
# Plan prose is display-only. Inspecting or comparing its wording turns AI prose into
# application state, which the architecture forbids.
if [ -d "$ROOT/Sources" ]; then
  member_checks=$(grep -rnE 'rationale[?!]?[[:space:]]*\.[_a-zA-Z][_a-zA-Z0-9]*' "$ROOT/Sources" 2>/dev/null || true)
  comparisons=$(grep -rnE '(rationale.*(==|!=|~=)|(==|!=|~=).*rationale)' "$ROOT/Sources" 2>/dev/null \
    | grep -vE 'rationale[[:space:]]*(==|!=)[[:space:]]*nil|nil[[:space:]]*(==|!=)[[:space:]]*[^[:space:]]*rationale' \
    || true)
  switches=$(grep -rnE '(switch|case).*rationale' "$ROOT/Sources" 2>/dev/null || true)
  advice_word_checks=$(grep -rnE 'displayAdvice[?!]?[[:space:]]*\.(contains|firstIndex|lastIndex)' "$ROOT/Sources" 2>/dev/null || true)
  advice_comparisons=$(grep -rnE '(displayAdvice.*(==|!=|~=)|(==|!=|~=).*displayAdvice)' "$ROOT/Sources" 2>/dev/null \
    | grep -vE 'displayAdvice[[:space:]]*(==|!=)[[:space:]]*nil|nil[[:space:]]*(==|!=)[[:space:]]*[^[:space:]]*displayAdvice' \
    || true)
  advice_switches=$(grep -rnE '(switch|case).*displayAdvice' "$ROOT/Sources" 2>/dev/null || true)
  label_word_checks=$(grep -rnE 'selection[?!]?\.[[:space:]]*label[?!]?[[:space:]]*\.(contains|hasPrefix|hasSuffix|range|firstIndex|lastIndex)' "$ROOT/Sources" 2>/dev/null || true)
  label_comparisons=$(grep -rnE '(selection[?!]?\.[[:space:]]*label.*(==|!=|~=)|(==|!=|~=).*selection[?!]?\.[[:space:]]*label)' "$ROOT/Sources" 2>/dev/null \
    | grep -vE 'label[[:space:]]*(==|!=)[[:space:]]*nil|nil[[:space:]]*(==|!=)[[:space:]]*[^[:space:]]*label' \
    || true)
  bad=$(printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n' \
    "$member_checks" "$comparisons" "$switches" \
    "$advice_word_checks" "$advice_comparisons" "$advice_switches" \
    "$label_word_checks" "$label_comparisons" \
    | sed '/^$/d' | sort -u)
  if [ -n "$bad" ]; then
    printf '%s\n' "$bad" | while read -r line; do
      fail "branching on display-only plan prose: $line"
    done
    FAIL=1
  else
    ok "no logic branches on display-only plan prose"
  fi
fi

echo ""
if [ "$FAIL" -eq 0 ]; then
  echo "boundaries: clean"
else
  echo "boundaries: VIOLATIONS FOUND"
fi
exit "$FAIL"
