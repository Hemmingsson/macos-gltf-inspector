# Shared constants and helpers for archive.sh / appcast.sh / release.sh.
# Source only; do not execute.

GH_REPO="${GH_REPO:-Hemmingsson/macos-gltf-inspector}"
FEED_URL="https://github.com/${GH_REPO}/releases/latest/download/appcast.xml"
PLACEHOLDER_ED_KEY="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
TEAM_ID="${TEAM_ID:-94A9N4B67S}"
NOTARY_PROFILE="${NOTARY_PROFILE:-glb-preview-notary}"
export GH_REPO FEED_URL

sparkle_root() {
  if [[ -n "${ROOT:-}" ]]; then
    printf '%s\n' "$ROOT"
    return
  fi
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

tool_status() {
  local name="$1"
  if command -v "$name" >/dev/null; then
    echo "  $name: ok"
  else
    echo "  $name: missing"
  fi
}

parse_project_versions() {
  local root
  root="$(sparkle_root)"
  if ! command -v python3 >/dev/null; then
    echo "missing python3 (needed to parse versions from project.yml)" >&2
    return 1
  fi

  local parsed
  parsed="$(
    python3 - "$root/project.yml" <<'PY'
import pathlib
import re
import sys

text = pathlib.Path(sys.argv[1]).read_text()
marketing = re.search(r'MARKETING_VERSION:\s*"([^"]+)"', text)
build = re.search(r'CURRENT_PROJECT_VERSION:\s*"([^"]+)"', text)
if not marketing or not build:
    sys.exit("could not parse MARKETING_VERSION / CURRENT_PROJECT_VERSION from project.yml")
print(marketing.group(1))
print(build.group(1))
PY
  )" || return 1

  MARKETING="$(printf '%s\n' "$parsed" | sed -n '1p')"
  BUILD="$(printf '%s\n' "$parsed" | sed -n '2p')"
  if [[ -z "$MARKETING" || -z "$BUILD" ]]; then
    echo "could not parse MARKETING_VERSION / CURRENT_PROJECT_VERSION from project.yml" >&2
    return 1
  fi
  TAG="v${MARKETING}"
  ZIP="$root/dist/glTFInspector-${MARKETING}.zip"
  NOTES="$root/dist/glTFInspector-${MARKETING}.md"
}

uses_placeholder_ed_key() {
  local root
  root="$(sparkle_root)"
  grep -qF "$PLACEHOLDER_ED_KEY" "$root/project.yml" "$root/GLTFInspector/UpdateConfig.swift"
}

zip_exported_app() {
  local export_dir="$1"
  local zip_path="$2"
  (
    cd "$export_dir"
    ditto -c -k --keepParent "glTF Inspector.app" "$zip_path"
  )
}

last_appcast_build() {
  local appcast="$1"
  python3 - "$appcast" <<'PY'
import sys
import xml.etree.ElementTree as ET

version_attr = "{http://www.andymatuschak.org/xml-namespaces/sparkle}version"
root = ET.parse(sys.argv[1]).getroot()
versions = []
for item in root.findall(".//item"):
    raw = item.attrib.get(version_attr)
    if raw is None:
        child = item.find(version_attr)
        raw = child.text if child is not None else None
    if raw and raw.strip().isdigit():
        versions.append(int(raw.strip()))
print(max(versions) if versions else "")
PY
}

require_newer_build() {
  local root appcast last
  root="$(sparkle_root)"
  appcast="$root/dist/updates/appcast.xml"
  [[ -f "$appcast" ]] || return 0
  last="$(last_appcast_build "$appcast")"
  [[ -n "$last" ]] || return 0
  if ! [[ "$BUILD" =~ ^[0-9]+$ ]]; then
    echo "CURRENT_PROJECT_VERSION must be an integer (got $BUILD)" >&2
    return 1
  fi
  if (( BUILD <= last )); then
    echo "CURRENT_PROJECT_VERSION $BUILD is not greater than last appcast build $last" >&2
    return 1
  fi
}
