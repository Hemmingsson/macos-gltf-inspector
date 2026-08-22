#!/usr/bin/env bash
# Check that the installed app and Quick Look extensions are registered.
#
#   ./scripts/verify.sh
#   ./scripts/build.sh             # rebuild + install, then this check
#   ./scripts/proof.sh             # still-renderer PNG + timed qlmanage
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="/Applications/glTF Inspector.app"

for arg in "$@"; do
  case "$arg" in
    -h|--help)
      sed -n '2,6p' "$0"
      exit 0
      ;;
    *)
      echo "unknown arg: $arg (pass a .glb to qlmanage -p, not this script)" >&2
      echo "usage: ./scripts/verify.sh" >&2
      exit 2
      ;;
  esac
done

if [[ ! -d "$APP" ]]; then
  echo "missing $APP — run ./scripts/build.sh or copy the app to /Applications and open it once" >&2
  exit 1
fi
for plug in PreviewExtension.appex ThumbnailExtension.appex; do
  if [[ ! -d "$APP/Contents/PlugIns/$plug" ]]; then
    echo "missing $APP/Contents/PlugIns/$plug" >&2
    exit 1
  fi
done

plugins="$(pluginkit -mAvvv)"
for id in lol.mattias.gltf-inspector.PreviewExtension lol.mattias.gltf-inspector.ThumbnailExtension; do
  if ! grep -q "$id" <<<"$plugins"; then
    echo "pluginkit does not list $id — open $APP once, then qlmanage -r" >&2
    exit 1
  fi
done

echo "ok $APP"
echo "ok PreviewExtension + ThumbnailExtension registered"
echo "proof:    $ROOT/scripts/proof.sh"
echo "logs:     log stream --style compact --info --predicate 'subsystem == \"lol.mattias.gltf-inspector\"'"
