#!/usr/bin/env bash
# Worktree-aware paths for scripts/dev.sh. Source only — do not execute directly.
set -euo pipefail

_DEV_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$_DEV_LIB_DIR/../.." && pwd)"

SLUG="$(git -C "$ROOT" branch --show-current 2>/dev/null | tr '/ ' '--' || true)"
if [[ -z "$SLUG" ]]; then
  SLUG="$(basename "$ROOT")"
fi

DERIVED_DATA="/tmp/GLTFInspector-${SLUG}-dd"
BUILD_PRODUCT="$DERIVED_DATA/Build/Products/Debug/glTF Inspector.app"
LOCAL_APP="$ROOT/.build/glTF Inspector.app"
CATALOG_APP="$DERIVED_DATA/Build/Products/Debug/DesignCatalog.app"
SYSTEM_APP="/Applications/glTF Inspector.app"
EXEC="$LOCAL_APP/Contents/MacOS/glTF Inspector"
LOG_DIR="$ROOT/.build/logs"
LOG_FILE="$LOG_DIR/debug.log"
MANIFEST="$ROOT/scripts/fixtures.manifest.json"

if [[ "$ROOT" == *"/.worktrees/"* ]]; then
  INSTALL_KIND=worktree
else
  INSTALL_KIND=main
fi

dev_fixture_path() {
  local id="$1"
  python3 - "$MANIFEST" "$id" "$ROOT" <<'PY'
import json, pathlib, sys
manifest_path, fixture_id, root = sys.argv[1:4]
manifest = json.loads(pathlib.Path(manifest_path).read_text())
for item in manifest["fixtures"]:
    if item["id"] == fixture_id:
        path = pathlib.Path(root) / item["path"]
        print(path)
        raise SystemExit(0)
raise SystemExit(f"unknown fixture: {fixture_id}")
PY
}

dev_fixture_ids() {
  python3 - "$MANIFEST" <<'PY'
import json, sys
manifest = json.loads(open(sys.argv[1]).read())
for item in manifest["fixtures"]:
    print(item["id"])
PY
}
