#!/usr/bin/env bash
# Check that the installed app and Quick Look extensions are registered.
#
#   ./scripts/verify.sh
#   ./scripts/build.sh             # rebuild + install, then this check
set -euo pipefail

APP="/Applications/glTF Inspector.app"

for arg in "$@"; do
  case "$arg" in
    -h|--help)
      sed -n '2,5p' "$0"
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

# The first (elected) copy must be the one inside /Applications. DerivedData / .build copies
# with a higher CFBundleShortVersionString steal Finder preview and show a blank failure UI.
elected="$(pluginkit -m -v -i lol.mattias.gltf-inspector.PreviewExtension 2>/dev/null || true)"
if ! grep -q "/Applications/glTF Inspector.app/Contents/PlugIns/PreviewExtension.appex" <<<"$elected"; then
  echo "PreviewExtension is not elected from $APP — unregister stale debug apps, open $APP, qlmanage -r" >&2
  echo "$elected" >&2
  exit 1
fi

echo "ok $APP"
echo "ok PreviewExtension + ThumbnailExtension registered (elected from /Applications)"
echo "logs:     log stream --style compact --info --predicate 'subsystem == \"lol.mattias.gltf-inspector\"'"
