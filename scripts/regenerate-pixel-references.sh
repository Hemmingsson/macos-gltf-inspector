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

# One xcodebuild run per renderer, WebKit first: it re-records the camera poses every renderer
# replays, so RealityKit must render after it. A renderer whose test folder is gone is skipped.
suite() {
  case "$1" in
    webkit) echo "PixelDiffWebKitRegeneration" ;;
    realitykit) echo "PixelDiffRealityKitRegeneration" ;;
    *) echo "unknown renderer: $1 (webkit|realitykit)" >&2; exit 2 ;;
  esac
}
folder() {
  case "$1" in
    webkit) echo "$ROOT/GLTFInspectorTests/WebKit" ;;
    realitykit) echo "$ROOT/GLTFInspectorTests/RealityKit" ;;
  esac
}

if [[ "${1:-}" == "--measure-noise" ]]; then
  SENTINEL="$REFS/MEASURE_NOISE"
  RENDERERS=(webkit realitykit)
else
  SENTINEL="$REFS/REGENERATE"
  if [[ $# -gt 0 ]]; then RENDERERS=("$@"); else RENDERERS=(webkit realitykit); fi
fi
trap 'rm -f "$SENTINEL"' EXIT

status=0
for renderer in "${RENDERERS[@]}"; do
  test_suite="$(suite "$renderer")"
  if [[ ! -d "$(folder "$renderer")" ]]; then
    echo "skip $renderer: renderer removed"
    continue
  fi
  echo "$renderer" >"$SENTINEL"
  LOG="$(mktemp -t pixel-references)"
  "$ROOT/scripts/dev.sh" test "-only-testing:GLTFInspectorTests/$test_suite" >"$LOG" 2>&1 || status=$?
  grep -E "^(noise|regenerated)|error:|TEST (SUCCEEDED|FAILED)" "$LOG" || true
  echo "full log ($renderer): $LOG"
  [[ "$status" -eq 0 ]] || break
done

echo
echo "Review before committing:"
git -C "$ROOT" status --short -- TestModels/References || true
exit "$status"
