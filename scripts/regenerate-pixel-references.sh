#!/usr/bin/env bash
# Rewrites pixel-diff reference PNGs under TestModels/References/<renderer>/ from the current
# renderers. Run this only when a renderer change legitimately changes output — the PNGs are
# the assertions, so regenerating makes the suite agree with whatever it does today.
#
#   ./scripts/regenerate-pixel-references.sh                 # webkit (re-records poses) + realitykit
#   ./scripts/regenerate-pixel-references.sh realitykit      # one renderer only
#   ./scripts/regenerate-pixel-references.sh --measure-noise # print the run-to-run noise floor
#
# Then LOOK at the regenerated PNGs before committing. A wrong reference bakes in a wrong
# answer for good, and `git diff --stat TestModels/References` tells you which ones moved.
#
# The generator is gated on a sentinel file rather than an environment variable: `xcodebuild
# test` does not forward the shell environment to the test process, so `FOO=1 xcodebuild ...`
# silently arrives as unset. The sentinel's content names the renderers to regenerate.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REFS="$ROOT/TestModels/References"

if [[ "${1:-}" == "--measure-noise" ]]; then
  SENTINEL="$REFS/MEASURE_NOISE"
  TEST="GLTFInspectorTests/PixelDiffNoiseFloor"
  : >"$SENTINEL"
else
  SENTINEL="$REFS/REGENERATE"
  TEST="GLTFInspectorTests/PixelDiffReferenceRegeneration"
  echo "$*" >"$SENTINEL"
fi
trap 'rm -f "$SENTINEL"' EXIT

LOG="$(mktemp -t pixel-references)"
status=0
"$ROOT/scripts/dev.sh" test "-only-testing:$TEST" >"$LOG" 2>&1 || status=$?
grep -E "^(noise|regenerated)|error:|TEST (SUCCEEDED|FAILED)" "$LOG" || true
echo "full log: $LOG"

echo
echo "Review before committing:"
git -C "$ROOT" status --short -- TestModels/References || true
exit "$status"
