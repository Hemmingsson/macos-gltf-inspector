#!/usr/bin/env bash
# Print compact load-bench summary from a redirected agent log (or harness JSON).
# Usage:
#   summarize-bench-log.sh /tmp/glb-preview-load-bench/agent-logs/EXP-012.log
#   summarize-bench-log.sh /tmp/glb-preview-load-bench/20260101-120000-EXP-012.json
set -euo pipefail

f="${1:-}"
if [[ -z "$f" || ! -f "$f" ]]; then
  echo "usage: $0 <logfile-or-harness.json>" >&2
  exit 2
fi

if [[ "$f" == *.json ]]; then
  python3 - "$f" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
total = d.get("sum_median_total_ms", d.get("sum_median_ms"))
load = d.get("sum_median_load_ms")
print(f"label={d.get('label','?')} sum_median_total_ms={total} sum_median_load_ms={load}")
for x in d.get("files") or []:
    tot = x.get("median_total_ms", x.get("median_ms"))
    err = x.get("error")
    extra = f" ERROR={err}" if err else ""
    print(f"  {x.get('id','?'):28} total={tot}{extra}")
PY
  exit 0
fi

# Prefer harness summary lines the script already prints
if grep -E '^label=|^wrote |sum_median_total_ms=' "$f" >/dev/null 2>&1; then
  grep -E '^label=|^wrote |sum_median_total_ms=|^  [0-9]' "$f" | tail -n 40
  exit 0
fi

# Fallback: find JSON path in log and summarize
json=$(grep -Eo '/tmp/glb-preview-load-bench/[^ ]+\.json' "$f" | tail -n 1 || true)
if [[ -n "$json" && -f "$json" ]]; then
  echo "from $json"
  exec "$0" "$json"
fi

echo "no summary found in $f (tail):" >&2
tail -n 30 "$f" >&2
exit 1
