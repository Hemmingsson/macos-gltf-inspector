#!/usr/bin/env bash
# Time EntityLoader.load + first still frame on the frozen 10-GLB set.
#   LABEL=EXP-005 ./scripts/load-bench.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="${LABEL:-unlabeled}"
MANIFEST="${GLB_LOAD_BENCH_MANIFEST:-$ROOT/experiments/manifest.json}"
OUT_DIR="${GLB_LOAD_BENCH_DIR:-/tmp/glb-preview-load-bench}"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$OUT_DIR/${STAMP}-${LABEL}.json"
DD="${GLB_LOAD_BENCH_DD:-/tmp/GLBPreview-dd-${LABEL}}"
CONFIG="$OUT_DIR/config.json"

mkdir -p "$OUT_DIR"
LOCK="$OUT_DIR/bench.lock"
echo "load-bench waiting for lock label=$LABEL"
# macOS has no flock(1); mkdir is an atomic lock.
while ! mkdir "$LOCK" 2>/dev/null; do
  sleep 2
done
trap 'rmdir "$LOCK" 2>/dev/null; rm -f "$CONFIG"' EXIT

python3 -c "import json,sys; json.dump({'label':sys.argv[1],'manifest':sys.argv[2],'out':sys.argv[3]}, open(sys.argv[4],'w'))" \
  "$LABEL" "$MANIFEST" "$OUT" "$CONFIG"

echo "load-bench label=$LABEL out=$OUT dd=$DD"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -scheme GLBPreview -destination 'platform=macOS' \
  -derivedDataPath "$DD" \
  -only-testing:GLBPreviewTests/LoadTimeBenchTests \
  test

echo "wrote $OUT"
python3 - "$OUT" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
total = d.get("sum_median_total_ms", d.get("sum_median_ms"))
load = d.get("sum_median_load_ms")
print(f"label={d['label']} sum_median_total_ms={total:.1f} sum_median_load_ms={load}")
for f in d["files"]:
    tot = f.get("median_total_ms", f.get("median_ms"))
    ld = f.get("median_load_ms")
    rd = f.get("median_first_render_ms")
    err = f.get("error")
    tot_s = f"{tot:.1f}" if isinstance(tot, (int, float)) else "—"
    ld_s = f"{ld:.1f}" if isinstance(ld, (int, float)) else "—"
    rd_s = f"{rd:.1f}" if isinstance(rd, (int, float)) else "—"
    extra = f" ERROR={err}" if err else ""
    print(f"  {f['id']:28} total={tot_s:>8}ms  load={ld_s:>8}ms  render={rd_s:>8}ms{extra}")
PY
