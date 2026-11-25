#!/usr/bin/env bash
# Sign the latest zip into dist/updates and refresh appcast.xml.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=sparkle-lib.sh
source "$SCRIPT_DIR/sparkle-lib.sh"

DIST_DIR="$ROOT/dist"
UPDATES_DIR="$DIST_DIR/updates"

if [[ $# -gt 1 ]]; then
  echo "usage: $0 [dist/glTFInspector-*.zip]" >&2
  exit 2
fi

if [[ $# -eq 1 ]]; then
  zip_path="$1"
  [[ "$zip_path" = /* ]] || zip_path="$ROOT/$zip_path"
else
  shopt -s nullglob
  zips=("$DIST_DIR"/glTFInspector-*.zip)
  shopt -u nullglob
  if [[ ${#zips[@]} -eq 0 ]]; then
    echo "missing zip (run ./scripts/archive.sh)" >&2
    exit 1
  fi
  IFS=$'\n' read -r zip_path < <(ls -t "${zips[@]}" | head -n 1)
fi

[[ -f "$zip_path" ]] || { echo "zip file not found: $zip_path" >&2; exit 1; }

mkdir -p "$UPDATES_DIR"
cp "$zip_path" "$UPDATES_DIR/"

notes_path="${zip_path%.zip}.md"
if [[ -f "$notes_path" ]]; then
  cp "$notes_path" "$UPDATES_DIR/"
fi

sparkle_bin="$("$ROOT/scripts/sparkle-tools.sh")"
"$sparkle_bin/generate_appcast" "$UPDATES_DIR"

updates_appcast="$UPDATES_DIR/appcast.xml"
[[ -f "$updates_appcast" ]] || { echo "generate_appcast did not create $updates_appcast" >&2; exit 1; }

"$ROOT/scripts/rewrite-appcast-urls.py" "$updates_appcast"
cp "$updates_appcast" "$DIST_DIR/appcast.xml"
echo "$DIST_DIR/appcast.xml"
