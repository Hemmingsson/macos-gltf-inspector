#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=sparkle-lib.sh
source "$ROOT/scripts/sparkle-lib.sh"

fixture="$ROOT/scripts/testdata/appcast-sample.xml"
tmp="$(mktemp "${TMPDIR:-/tmp}/appcast-sample.XXXXXX.xml")"

cleanup() {
  rm -f "$tmp"
}
trap cleanup EXIT

cp "$fixture" "$tmp"
"$ROOT/scripts/rewrite-appcast-urls.py" "$tmp"

base="https://github.com/${GH_REPO}/releases/download"
grep -F "${base}/v1.2.0/GLBPreview%201.2.0.zip" "$tmp" >/dev/null
grep -F "${base}/v1.2.0/GLBPreview-1.2.0.zip" "$tmp" >/dev/null
grep -F "${base}/v1.1.0/GLBPreview-1.1.0.zip" "$tmp" >/dev/null
grep -F "${base}/v1.1.0/GLBPreview-1.1.0.md" "$tmp" >/dev/null
grep -F "${base}/v1.2.0/GLBPreview-1.2.0.md" "$tmp" >/dev/null

echo "ok"
