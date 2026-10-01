#!/usr/bin/env bash
# Reliable visual proof: the still-renderer test writes /tmp/GLTFInspector-proof.png.
# qlmanage hangs headless and on a stale system plugin, so it runs only on request.
#
#   ./scripts/proof.sh              # StillRenderProofTests into this branch's DerivedData
#   ./scripts/proof.sh --qlmanage   # also a timed qlmanage thumbnail (needs a GUI session)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT=/tmp/GLTFInspector-proof.png
QLMANAGE=0

for arg in "$@"; do
  case "$arg" in
    -h|--help)
      sed -n '2,6p' "$0"
      exit 0
      ;;
    --qlmanage)
      QLMANAGE=1
      ;;
    *)
      echo "unknown arg: $arg" >&2
      echo "usage: ./scripts/proof.sh [--qlmanage]" >&2
      exit 2
      ;;
  esac
done

rm -f "$OUT"
echo "still renderer: StillRenderProofTests → $OUT"
"$ROOT/scripts/dev.sh" test -only-testing:GLTFInspectorTests/StillRenderProofTests

if [[ ! -f "$OUT" ]]; then
  echo "missing $OUT" >&2
  exit 1
fi
echo "ok $OUT ($(wc -c < "$OUT") bytes)"

if (( QLMANAGE )); then
  QL_DIR="${TMPDIR:-/tmp}/GLTFInspector-qlmanage"
  rm -rf "$QL_DIR"
  mkdir -p "$QL_DIR"
  echo "qlmanage (12s timeout):"
  if perl -e 'alarm 12; exec @ARGV' -- qlmanage -t -o "$QL_DIR" "$ROOT/TestModels/Fixture Models/tiny.glb"; then
    find "$QL_DIR" -type f -print
  else
    echo "qlmanage timed out or failed — use $OUT as proof"
  fi
fi
