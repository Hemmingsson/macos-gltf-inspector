#!/usr/bin/env bash
# Rewrites every pixel-diff reference PNG and TestModels/References/manifest.json from the
# current renderer. Run this only when a renderer upgrade legitimately changes output — the
# PNGs are the assertions, so regenerating makes the suite agree with whatever it does today.
#
#   ./scripts/regenerate-pixel-references.sh
#
# Then LOOK at the regenerated PNGs before committing. A wrong reference bakes in a wrong
# answer for good, and `git diff --stat TestModels/References` tells you which ones moved.
#
# The generator is gated on a sentinel file rather than an environment variable: `xcodebuild
# test` does not forward the shell environment to the test process, so `FOO=1 xcodebuild ...`
# silently arrives as unset.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SENTINEL="$ROOT/TestModels/References/REGENERATE"

if [[ -z "$(find "$ROOT/TestModels/Khronos samples" -name '*.glb' -print -quit 2>/dev/null)" ]]; then
  echo "No Khronos samples under TestModels/Khronos samples — run ./scripts/fetch-test-models.sh" >&2
  exit 1
fi

mkdir -p "$(dirname "$SENTINEL")"
touch "$SENTINEL"
trap 'rm -f "$SENTINEL"' EXIT

cd "$ROOT"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -scheme GLTFInspector -destination 'platform=macOS' \
  -derivedDataPath "${GLB_DERIVED_DATA:-/tmp/GLTFInspector-dd}" \
  -only-testing:GLTFInspectorTests/PixelDiffReferenceRegeneration \
  test

echo
echo "Regenerated. Review before committing:"
git -C "$ROOT" diff --stat -- TestModels/References || true
