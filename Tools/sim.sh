#!/bin/bash
# Build, install, launch, and screenshot the app on a simulator — headless.
#
# Simulator.app is never opened. `simctl` talks to CoreSimulator directly, so this
# works over SSH with no display, no VNC, and no screen sharing. That keeps the
# headless-development requirement honest for the app as well as the package.
#
# Usage:
#   ./Tools/sim.sh                    build, launch, screenshot
#   ./Tools/sim.sh --shot-only        screenshot whatever is on screen now
#   ./Tools/sim.sh --video 8          record 8 seconds instead of a screenshot
#
# Output lands in build/sim/ so it is easy to scp back to your laptop.

set -euo pipefail

cd "$(dirname "$0")/.."

DEVICE="${FORGE_SIM_DEVICE:-iPhone 16 Pro}"
BUNDLE_ID="dev.forge.photographer"
OUT_DIR="build/sim"
SHOT_ONLY=0
VIDEO_SECONDS=0

while [ $# -gt 0 ]; do
  case "$1" in
    --shot-only) SHOT_ONLY=1; shift ;;
    --video) VIDEO_SECONDS="${2:-6}"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

mkdir -p "$OUT_DIR"

# Boot on demand. An already-booted device reports an error that is not one.
if ! xcrun simctl list devices booted | grep -q "$DEVICE"; then
  echo "booting $DEVICE"
  xcrun simctl boot "$DEVICE"
fi
xcrun simctl bootstatus "$DEVICE" -b >/dev/null

if [ "$SHOT_ONLY" -eq 0 ]; then
  echo "building"
  make app >/dev/null

  # Ask xcodebuild where it put the bundle rather than guessing the DerivedData hash.
  APP_PATH=$(xcodebuild -project Forge.xcodeproj -scheme ForgePhotographer \
    -destination 'generic/platform=iOS Simulator' -configuration Debug \
    -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/ TARGET_BUILD_DIR/ {d=$2} / FULL_PRODUCT_NAME/ {n=$2} END {print d "/" n}')

  if [ ! -d "$APP_PATH" ]; then
    echo "could not locate the built app at: $APP_PATH" >&2
    exit 1
  fi

  echo "installing $(basename "$APP_PATH")"
  xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl install "$DEVICE" "$APP_PATH"
  xcrun simctl launch "$DEVICE" "$BUNDLE_ID" >/dev/null
  # Give SwiftUI a moment to lay out before capturing.
  sleep 3
fi

STAMP=$(date +%Y%m%d-%H%M%S)

if [ "$VIDEO_SECONDS" -gt 0 ]; then
  VIDEO="$OUT_DIR/forge-$STAMP.mp4"
  echo "recording ${VIDEO_SECONDS}s"
  xcrun simctl io "$DEVICE" recordVideo --codec h264 "$VIDEO" &
  RECORDER=$!
  sleep "$VIDEO_SECONDS"
  # SIGINT is how simctl is told to finalise the file; SIGKILL truncates it.
  kill -INT "$RECORDER" 2>/dev/null || true
  wait "$RECORDER" 2>/dev/null || true
  echo "video: $VIDEO"
else
  SHOT="$OUT_DIR/forge-$STAMP.png"
  xcrun simctl io "$DEVICE" screenshot "$SHOT" >/dev/null 2>&1
  echo "screenshot: $SHOT"
fi

echo
echo "copy it back with:"
echo "  scp $(whoami)@$(hostname -s):$(pwd)/$OUT_DIR/'*' ."
