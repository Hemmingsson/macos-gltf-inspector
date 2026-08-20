#!/usr/bin/env bash
# Campaign cold-start for glb-load-experiments.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
cd "$ROOT"

python3 - <<'PY'
import json
from pathlib import Path
d = json.loads(Path("experiments/results.json").read_text())
rc = d.get("recorded_control") or {}
aq = d.get("accepted_queue") or []
batches = d.get("reject_only_batches") or 0
print("champion:", d.get("champion"), "ms:", d.get("champion_sum_median_total_ms"))
print("control.sha:", (rc.get("sha") or "")[:12], "ms:", rc.get("sum_median_total_ms"))
print("accepted_queue:", len(aq), [x.get("id") for x in aq])
print("checkpoints:", len(d.get("checkpoints") or []))
print("reject_only_batches:", batches)
print("research_allowed:", "no — abandon" if batches >= 3 and not aq else "yes")
print("noise:", d.get("noise_rule", ""))
PY

echo "--- residual ---"
if [[ -f experiments/residual-map.json ]]; then
  python3 - <<'PY'
import json
from pathlib import Path
m = json.loads(Path("experiments/residual-map.json").read_text())
print("sha:", (m.get("sha") or "")[:12], "sum:", m.get("sum_median_total_ms"), "noise_floor:", round(m.get("noise_floor_ms") or 0, 1))
print("phases:", "yes" if m.get("phases") else "no", "src:", m.get("phases_source") or m.get("source"))
for a in sorted(m.get("assets") or [], key=lambda x: x.get("share_pct") or 0, reverse=True)[:6]:
    print(f"  {a['id']:28} {a['share_pct']:5.1f}%  lane={a['lane_hint']}")
if m.get("phases"):
    for k, v in m["phases"].items():
        if v.get("present"):
            print(f"  phase {k}: {v['sum_ms']:.0f}ms")
PY
else
  echo "MISSING residual-map.json — run update-residual-map.sh; research blocked"
fi

echo "--- champion / notes ---"
python3 - <<'PY'
from pathlib import Path
text = Path("experiments/WHAT-WE-TRIED.md").read_text().splitlines()
out, skip = [], False
for line in text:
    if line.startswith("## Tried"):
        skip = True
        continue
    if skip and line.startswith("## "):
        skip = False
    if line.startswith("## Residual"):
        skip = True  # residual-map section above is authoritative
        continue
    if not skip:
        out.append(line)
print("\n".join(out).strip())
PY

echo "--- dex ---"
if command -v dex >/dev/null; then
  dex list 7uyt0wel 2>/dev/null | head -15 || true
else
  echo "dex not on PATH"
fi

n=$(ls /tmp/glb-preview-load-bench/set/*.glb 2>/dev/null | wc -l | tr -d ' ')
echo "--- corpus: $n glb (expect 10) ---"
lock=/tmp/glb-preview-load-bench/bench.lock
[[ -d "$lock" ]] && echo "WARN: bench.lock held" || echo "bench.lock: free"
