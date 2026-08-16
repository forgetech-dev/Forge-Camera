#!/bin/bash
# Type-check the whole iOS graph with the device SDK, without xcodebuild.
#
# `xcodebuild` needs Xcode's installed iOS platform. When that is missing, this is
# the strongest verification still available: it compiles each package boundary in
# dependency order and type-checks the app against them, under Swift 6 with complete
# strict concurrency and warnings as errors — the same settings the app target uses.
#
# It does NOT link, produce a bundle, or prove anything about device behaviour.
#
# Usage: ./Tools/typecheck-ios.sh

set -euo pipefail

cd "$(dirname "$0")/.."

SDK=$(xcrun --sdk iphoneos --show-sdk-path)
MODULES=$(mktemp -d)
trap 'rm -rf "$MODULES"' EXIT

# An array, not a string. A quoted string is passed as one argument and swiftc
# rejects it — which silently turned an earlier verification into a false pass.
COMMON=(
  -sdk "$SDK"
  -target arm64-apple-ios18.0
  -swift-version 6
  -strict-concurrency=complete
  -warnings-as-errors
  -package-name ForgeCamera
)

emit_module() {
  local name=$1
  shift
  printf '  %-14s' "$name"
  xcrun swiftc "${COMMON[@]}" -I "$MODULES" \
    -emit-module -emit-module-path "$MODULES/$name.swiftmodule" \
    -module-name "$name" "$@"
  printf 'ok\n'
}

echo "iOS device-SDK type-check (arm64-apple-ios18.0, Swift 6, strict concurrency)"

# Dependency order matters: each module is compiled against the previous ones.
emit_module ForgeCore $(find Sources/ForgeCore -name '*.swift')
emit_module ForgeFrame $(find Sources/ForgeFrame -name '*.swift')
emit_module ForgeCapture $(find Sources/ForgeCapture -name '*.swift')

printf '  %-14s' "App"
xcrun swiftc "${COMMON[@]}" -I "$MODULES" -typecheck App/*.swift
printf 'ok\n'

echo "iOS type-check: clean"
