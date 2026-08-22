#!/usr/bin/env bash
# Reliable visual proof. qlmanage can hang on a stale system plugin;
# the still-renderer test writes /tmp/GLTFInspector-proof.png instead.
#
#   ./scripts/proof.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${GLB_PROOF_PNG:-/tmp/GLTFInspector-proof.png}"
QL_DIR="${TMPDIR:-/tmp}/GLTFInspector-qlmanage"
rm -rf "$QL_DIR"
mkdir -p "$QL_DIR"

echo "still renderer: xcodebuild StillRenderProofTests → $OUT"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -scheme GLTFInspector -destination 'platform=macOS' \
  -derivedDataPath /tmp/GLTFInspector-dd \
  -only-testing:GLTFInspectorTests/StillRenderProofTests \
  test

if [[ ! -f "$OUT" ]]; then
  echo "missing $OUT" >&2
  exit 1
fi
echo "ok $OUT ($(wc -c < "$OUT") bytes)"

echo "qlmanage (12s timeout, optional):"
if perl -e 'alarm 12; exec @ARGV' -- qlmanage -t -o "$QL_DIR" "$ROOT/TestModels/Fixture Models/tiny.glb"; then
  find "$QL_DIR" -type f -print
else
  echo "qlmanage timed out or failed — use $OUT as proof"
fi
