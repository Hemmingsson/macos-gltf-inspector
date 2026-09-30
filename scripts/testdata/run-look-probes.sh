#!/usr/bin/env bash
# Runs the opt-in look probes (GLTFInspectorTests/CrossRenderer/LookProbeTests.swift) on both renderers.
# Gated on a sentinel file, like regenerate-pixel-references.sh: `xcodebuild test` does not
# forward the shell environment. Output: `lookprobe …` lines + /tmp/GLTFInspector-look-probes/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SENTINEL="$ROOT/TestModels/Fixture Models/probes/RUN_LOOK_PROBES"
: >"$SENTINEL"
trap 'rm -f "$SENTINEL"' EXIT

LOG="$(mktemp -t look-probes)"
status=0
"$ROOT/scripts/dev.sh" test "-only-testing:GLTFInspectorTests/LookProbeTests" >"$LOG" 2>&1 || status=$?
grep -E "^lookprobe|error:|TEST (SUCCEEDED|FAILED)" "$LOG" || true
echo "full log: $LOG"
exit "$status"
