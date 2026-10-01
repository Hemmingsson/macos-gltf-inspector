#!/usr/bin/env bash
# Tidy-loop metrics: Periphery, SwiftLint (size/complexity), jscpd (duplication), LOC.
# Writes .agents/research/tidy-baseline/<label>/ and prints the summary + delta vs summary-0.
#
#   ./scripts/tidy-metrics.sh [label] [tests]   # label defaults to the short HEAD sha;
#                                              # tests = passing test count to record (optional)
#
# Needs: periphery, swiftlint (brew), npx (jscpd@5.4.0), xcodegen.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

LABEL="${1:-$(git rev-parse --short HEAD)}"
TESTS="${2:-}"
BASE="$ROOT/.agents/research/tidy-baseline"
OUT="$BASE/$LABEL"
PROD_DIRS=(GLTFCore RendererRealityKit RendererWebKit GLTFInspector PreviewUI DesignSystem DesignCatalog PreviewExtension ThumbnailExtension)
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

for tool in periphery swiftlint npx xcodegen; do
  command -v "$tool" >/dev/null || { echo "missing $tool" >&2; exit 1; }
done
mkdir -p "$OUT"

echo "periphery…" >&2
xcodegen generate >/dev/null
# Periphery passes its own DerivedData; do not add -derivedDataPath.
periphery scan --project GLTFInspector.xcodeproj --schemes GLTFInspector DesignCatalog \
  --retain-codable-properties --retain-swift-ui-previews --relative-results --quiet \
  -- -destination 'platform=macOS' >"$OUT/periphery.txt"

echo "swiftlint…" >&2
swiftlint lint --config "$BASE/swiftlint-metrics.yml" --quiet --no-cache "${PROD_DIRS[@]}" 2>/dev/null \
  | sed "s|^$ROOT/||" | sort >"$OUT/swiftlint.txt" || true

echo "jscpd…" >&2
JSCPD_DIR="$(mktemp -d)"
npx -y jscpd@5.4.0 "${PROD_DIRS[@]}" --format swift --min-tokens 70 --min-lines 6 \
  --ignore "**/web-renderer/**,**/Vendor/**" --reporters json --output "$JSCPD_DIR" --silent >/dev/null
mv "$JSCPD_DIR/jscpd-report.json" "$OUT/jscpd.json"
rm -rf "$JSCPD_DIR"

loc="$(git ls-files -z '*.swift' '*.mm' '*.h' '*.sh' '*.py' | xargs -0 cat | wc -l | tr -d ' ')"
periphery_count="$(grep -c ': warning:' "$OUT/periphery.txt" || true)"
swiftlint_count="$(grep -cE ': (warning|error):' "$OUT/swiftlint.txt" || true)"
clones="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["statistics"]["total"]["clones"])' "$OUT/jscpd.json")"

summary="loc=$loc periphery=$periphery_count swiftlint=$swiftlint_count jscpd_clones=$clones"
[[ -n "$TESTS" ]] && summary+=" tests=$TESTS"
echo "$summary" >"$OUT/summary.txt"

echo "$summary"
python3 - "$BASE/summary-0.txt" "$OUT/summary.txt" <<'PY'
import sys
def read(p):
    return dict(kv.split("=", 1) for kv in open(p).read().split())
base, now = read(sys.argv[1]), read(sys.argv[2])
print("delta vs summary-0: " + " ".join(
    f"{k}={int(now[k]) - int(base[k]):+d}" for k in now if k in base))
PY
echo "wrote $OUT" >&2
