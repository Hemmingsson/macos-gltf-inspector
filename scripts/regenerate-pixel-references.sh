#!/usr/bin/env bash
# Rewrites the pixel-diff reference PNGs under TestModels/References/ (and the camera poses in
# its manifest) from the current page. Run this only when a page change legitimately changes
# output — the PNGs are the assertions, so regenerating makes the suite agree with whatever it
# does today.
#
#   ./scripts/regenerate-pixel-references.sh                 # re-record poses + references
#   ./scripts/regenerate-pixel-references.sh --measure-noise # print the run-to-run noise floor
#
# Then LOOK at the regenerated PNGs before committing. A wrong reference bakes in a wrong
# answer for good, and `git diff --stat TestModels/References` tells you which ones moved.
#
# The generator is gated on a sentinel file rather than an environment variable: `xcodebuild
# test` does not forward the shell environment to the test process, so `FOO=1 xcodebuild ...`
# silently arrives as unset.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REFS="$ROOT/TestModels/References"

case "${1:-}" in
  "") SENTINEL="$REFS/REGENERATE" ;;
  --measure-noise) SENTINEL="$REFS/MEASURE_NOISE" ;;
  *) echo "usage: $0 [--measure-noise]" >&2; exit 2 ;;
esac
trap 'rm -f "$SENTINEL"' EXIT
touch "$SENTINEL"

status=0
LOG="$(mktemp -t pixel-references)"
"$ROOT/scripts/dev.sh" test "-only-testing:GLTFInspectorTests/PixelDiffWebKitRegeneration" >"$LOG" 2>&1 || status=$?
grep -E "^(noise|regenerated)|error:|TEST (SUCCEEDED|FAILED)" "$LOG" || true
echo "full log: $LOG"

echo
echo "Review before committing:"
git -C "$ROOT" status --short -- TestModels/References || true
exit "$status"
