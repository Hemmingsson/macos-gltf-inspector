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
grep -F "${base}/v1.2.0/glTFInspector-1.2.0.zip" "$tmp" >/dev/null
grep -F "${base}/v1.1.0/glTFInspector-1.1.0.zip" "$tmp" >/dev/null
grep -F "${base}/v1.1.0/glTFInspector-1.1.0.md" "$tmp" >/dev/null
grep -F "${base}/v1.2.0/glTFInspector-1.2.0.md" "$tmp" >/dev/null

# Delta enclosures are nested under sparkle:deltas, but belong to the target release.
python3 - "$tmp" <<'PYTEST'
import sys
import xml.etree.ElementTree as ET
p = sys.argv[1]
tree = ET.parse(p)
item = tree.find(".//item")
deltas = ET.SubElement(item, "{http://www.andymatuschak.org/xml-namespaces/sparkle}deltas")
ET.SubElement(deltas, "enclosure", url="file:///tmp/update.delta")
tree.write(p)
PYTEST
"$ROOT/scripts/rewrite-appcast-urls.py" "$tmp"
grep -F "${base}/v1.2.0/update.delta" "$tmp" >/dev/null
echo "ok"
