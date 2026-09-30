#!/usr/bin/env bash
# Cold/warm WebKit first-paint bench. Prints `wk-fp` lines and a summary table.
#
#   ./scripts/webkit-first-paint-bench.sh
#   ./scripts/webkit-first-paint-bench.sh --label control
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/dev-env.sh
source "$ROOT/scripts/lib/dev-env.sh"

LABEL="control"
if [[ "${1:-}" == "--label" ]]; then
  LABEL="${2:?label}"
fi

OUT_DIR="${WEBKIT_FP_BENCH_DIR:-/tmp/glb-preview-webkit-fp-bench}"
mkdir -p "$OUT_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
RAW="$OUT_DIR/${STAMP}-${LABEL}.log"

cd "$ROOT"
command -v xcodegen >/dev/null || {
  echo "install XcodeGen: brew install xcodegen" >&2
  exit 1
}
xcodegen generate

echo "webkit-first-paint-bench label=$LABEL derived=$DERIVED_DATA" | tee "$RAW"

run_suite() {
  local mode="$1"
  local asset="${2:-}"
  if [[ -n "$asset" ]]; then
    printf '%s %s\n' "$mode" "$asset" >"$OUT_DIR/request"
  else
    printf '%s\n' "$mode" >"$OUT_DIR/request"
  fi
  echo "--- suite mode=$mode asset=${asset:-all} ---" | tee -a "$RAW"
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
    xcodebuild -scheme GLTFInspector -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    -only-testing:GLTFInspectorTests/RendererTimingBenchTests \
    test 2>&1 | tee -a "$RAW"
}

# Fresh process per asset: this is Quick Look / first-window time.
run_suite proc-cold tiny.glb
run_suite proc-cold BoomBox.glb
run_suite proc-cold Corset.glb
# Same-process new hosts + warm reuse (window already open / thumbnail reuse).
run_suite full
rm -f "$OUT_DIR/request"

echo
echo "=== $LABEL wk-fp lines ==="
rg -n '^wk-fp |wk-fp ' "$RAW" || true

python3 - "$RAW" "$LABEL" <<'PY'
import re, statistics, sys
from collections import defaultdict

path, label = sys.argv[1], sys.argv[2]
text = open(path, errors="replace").read()
# xcodebuild often prefixes test output; keep the payload after `wk-fp`.
line_re = re.compile(
    r"wk-fp (proc-cold|cold|warm) (\S+) ([0-9.]+) ([0-9.]+) ([0-9.]+) ([0-9.]+) "
    r"([0-9.]+) ([0-9.]+) ([0-9.]+) ([0-9.]+) ([0-9.]+) ([0-9.]+) ([0-9.]+)"
)
rows = defaultdict(list)
for raw in text.splitlines():
    m = line_re.search(raw)
    if not m:
        continue
    mode, name = m.group(1), m.group(2)
    nums = [float(m.group(i)) for i in range(3, 14)]
    rows[(mode, name)].append({
        "bytesMB": nums[0],
        "pageMs": nums[1],
        "iblMs": nums[2],
        "loadMs": nums[3],
        "parseMs": nums[4],
        "fitMs": nums[5],
        "stillMs": nums[6],
        "visibleMs": nums[7],
        "totalMs": nums[8],
        "px": nums[9],
        "tris": nums[10],
    })

if not rows:
    print("no wk-fp data rows parsed", file=sys.stderr)
    sys.exit(1)

def med(values):
    return statistics.median(values)

print(f"\n=== {label} median ===")
print(f"{'mode':<9} {'name':<20} {'n':>2} {'page':>6} {'ibl':>6} {'load':>6} {'parse':>6} {'fit':>5} {'still':>6} {'visible':>8} {'total':>7}")
for (mode, name), samples in sorted(rows.items()):
    n = len(samples)
    print(
        f"{mode:<9} {name:<20} {n:>2} "
        f"{med([s['pageMs'] for s in samples]):>6.0f} "
        f"{med([s['iblMs'] for s in samples]):>6.0f} "
        f"{med([s['loadMs'] for s in samples]):>6.0f} "
        f"{med([s['parseMs'] for s in samples]):>6.0f} "
        f"{med([s['fitMs'] for s in samples]):>5.0f} "
        f"{med([s['stillMs'] for s in samples]):>6.0f} "
        f"{med([s['visibleMs'] for s in samples]):>8.0f} "
        f"{med([s['totalMs'] for s in samples]):>7.0f}"
    )
print(f"\nraw {path}")
PY
