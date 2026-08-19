#!/usr/bin/env bash
# Generate, build, and install GLBPreview.app to /Applications, then check plugins.
#
#   ./scripts/build.sh
#   ./scripts/verify.sh            # check only (no rebuild)
#   qlmanage -p scripts/tiny.glb   # preview proof
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="/Applications/GLBPreview.app"

for arg in "$@"; do
  case "$arg" in
    -h|--help)
      sed -n '2,6p' "$0"
      exit 0
      ;;
    *)
      echo "unknown arg: $arg" >&2
      echo "usage: ./scripts/build.sh" >&2
      exit 2
      ;;
  esac
done

command -v xcodegen >/dev/null || { echo "install XcodeGen: brew install xcodegen" >&2; exit 1; }
cd "$ROOT"
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -scheme GLBPreview -destination 'platform=macOS' \
  -derivedDataPath /tmp/GLBPreview-dd build
rm -rf "$APP"
cp -R /tmp/GLBPreview-dd/Build/Products/Debug/GLBPreview.app "$APP"
rm -rf "$APP/Contents/PlugIns/GLBPreviewTests.xctest"
qlmanage -r
open "$APP"
sleep 2
exec "$ROOT/scripts/verify.sh"
