#!/usr/bin/env bash
# Build experiments/residual-map.json from champion control (+ optional phase overlay).
#   ./update-residual-map.sh [raw-bench.json] [phases-bench.json]
# Default raw: recorded_control.raw. Default phases: experiments/results/cp-002-phases.json if present.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
cd "$ROOT"

python3 - "$ROOT" "${1:-}" "${2:-}" <<'PY'
import json, sys
from pathlib import Path
from datetime import datetime, timezone

root = Path(sys.argv[1])
raw_arg = sys.argv[2] if len(sys.argv) > 2 else ""
phases_arg = sys.argv[3] if len(sys.argv) > 3 else ""
results = json.loads((root / "experiments/results.json").read_text())
rc = results.get("recorded_control") or {}
out_path = root / "experiments/residual-map.json"

def load_json(path: Path):
    return json.loads(path.read_text()) if path.is_file() else None

raw = load_json(Path(raw_arg)) if raw_arg else None
source = raw_arg or None
if raw is None and rc.get("raw"):
    source = rc["raw"]
    raw = load_json(Path(source))

phases_path = Path(phases_arg) if phases_arg else root / "experiments/results/cp-002-phases.json"
phases_raw = load_json(phases_path)
phases_by_id = {f["id"]: f for f in (phases_raw or {}).get("files") or []}

# Must match LoadPhaseTimer.Phase raw values.
PHASE_KEYS = (
    "file_read_ms", "parse_ms", "decode_ms",
    "texture_ms", "scene_build_ms", "gpu_upload_ms",
)

def lane_hint(asset_id: str, share_pct: float) -> str:
    if asset_id.startswith(("09-", "10-", "07-")):
        return "C"
    if asset_id.startswith("08-"):
        return "B"
    if asset_id.startswith("06-") and share_pct >= 5:
        return "B"
    return "A"

assets, phases, sum_total = [], None, None
if raw:
    files = raw.get("files") or []
    sum_total = raw.get("sum_median_total_ms") or sum(
        (f.get("median_total_ms") or 0) for f in files
    )
    phase_sums = {k: 0.0 for k in PHASE_KEYS}
    phase_hit = {k: False for k in PHASE_KEYS}
    for f in files:
        ms = f.get("median_total_ms")
        if not isinstance(ms, (int, float)):
            continue
        share = (100.0 * ms / sum_total) if sum_total else 0.0
        # Prefer phase overlay file; else phases embedded in raw.
        src = phases_by_id.get(f.get("id")) or f
        asset_phases = {}
        for k in PHASE_KEYS:
            v = src.get(k)
            if isinstance(v, (int, float)):
                asset_phases[k] = v
                phase_sums[k] += v
                phase_hit[k] = True
        assets.append({
            "id": f.get("id"),
            "median_total_ms": ms,
            "median_load_ms": f.get("median_load_ms"),
            "share_pct": round(share, 1),
            "lane_hint": lane_hint(f.get("id") or "", share),
            "phases": asset_phases or None,
        })
    if any(phase_hit.values()):
        phases = {k: {"sum_ms": phase_sums[k], "present": True} for k, hit in phase_hit.items() if hit}

if not assets:
    sum_total = results.get("champion_sum_median_total_ms")
    print("WARN: no raw bench; champion totals only", file=sys.stderr)

payload = {
    "champion": results.get("champion"),
    "sha": rc.get("sha"),
    "source": source,
    "sum_median_total_ms": sum_total,
    "recorded_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "noise_floor_ms": (0.03 * sum_total) if isinstance(sum_total, (int, float)) else None,
    "assets": assets,
    "phases": phases,
    "reject_only_batches": results.get("reject_only_batches") or 0,
}
if phases_raw and phases:
    payload["phases_source"] = str(phases_path)
if assets:
    ranked = sorted(assets, key=lambda a: a["share_pct"], reverse=True)
    payload["top"] = [{"id": a["id"], "share_pct": a["share_pct"]} for a in ranked[:3]]

out_path.write_text(json.dumps(payload, indent=2) + "\n")
print(f"wrote {out_path} sum={sum_total}")
for a in sorted(assets, key=lambda x: x["share_pct"], reverse=True):
    print(f"  {a['id']:28} {a['share_pct']:5.1f}%  lane={a['lane_hint']}")
if phases:
    print("phases:", ", ".join(f"{k}={v['sum_ms']:.0f}" for k, v in phases.items()))
else:
    print("phases: none")
PY
