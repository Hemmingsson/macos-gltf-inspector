#!/usr/bin/env bash
# Check the installed Quick Look extensions.
#
#   ./scripts/verify.sh              # app + pluginkit
#   ./scripts/verify.sh --build      # xcodegen + xcodebuild + install + README assets
#   qlmanage -p scripts/tiny.glb     # interactive preview (separate)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="/Applications/GLBPreview.app"
BUILD=0

for arg in "$@"; do
  case "$arg" in
    --build) BUILD=1 ;;
    -h|--help)
      sed -n '2,7p' "$0"
      exit 0
      ;;
    *)
      echo "unknown arg: $arg (pass a .glb to qlmanage -p, not this script)" >&2
      exit 2
      ;;
  esac
done

if [[ "$BUILD" -eq 1 ]]; then
  command -v xcodegen >/dev/null || { echo "install XcodeGen: brew install xcodegen" >&2; exit 1; }
  cd "$ROOT"
  xcodegen generate
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
    xcodebuild -scheme GLBPreview -destination 'platform=macOS' \
    -derivedDataPath /tmp/GLBPreview-dd build
  rm -rf "$APP"
  cp -R /tmp/GLBPreview-dd/Build/Products/Debug/GLBPreview.app "$APP"
  rm -rf "$APP/Contents/PlugIns/GLBPreviewTests.xctest" "$APP/Contents/Library/Spotlight"
  qlmanage -r
  open "$APP"
  sleep 2
  "$ROOT/scripts/publish.sh"
fi

if [[ ! -d "$APP" ]]; then
  echo "missing $APP — run ./scripts/verify.sh --build or copy the app to /Applications and open it once" >&2
  exit 1
fi
for plug in PreviewExtension.appex ThumbnailExtension.appex; do
  if [[ ! -d "$APP/Contents/PlugIns/$plug" ]]; then
    echo "missing $APP/Contents/PlugIns/$plug" >&2
    exit 1
  fi
done

plugins="$(pluginkit -mAvvv)"
for id in com.laurie.GLBPreview.PreviewExtension com.laurie.GLBPreview.ThumbnailExtension; do
  if ! grep -q "$id" <<<"$plugins"; then
    echo "pluginkit does not list $id — open $APP once, then qlmanage -r" >&2
    exit 1
  fi
done

echo "ok $APP"
echo "ok PreviewExtension + ThumbnailExtension registered"
echo "preview:  qlmanage -p $ROOT/scripts/tiny.glb"
echo "icon:     qlmanage -t $ROOT/scripts/tiny.glb"
echo "logs:     log stream --style compact --info --predicate 'subsystem == \"com.laurie.GLBPreview\"'"
