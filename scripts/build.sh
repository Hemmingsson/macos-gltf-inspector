#!/usr/bin/env bash
# Generate, build, and install "glTF Inspector.app" to /Applications, then check plugins.
#
#   ./scripts/build.sh
#   ./scripts/build.sh --install-only   # build + copy to /Applications (no open/verify)
#   ./scripts/verify.sh            # check only (no rebuild)
#   ./scripts/proof.sh             # still-renderer PNG + timed qlmanage
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="/Applications/glTF Inspector.app"
INSTALL_ONLY=0

for arg in "$@"; do
  case "$arg" in
    -h|--help)
      sed -n '2,7p' "$0"
      exit 0
      ;;
    --install-only)
      INSTALL_ONLY=1
      ;;
    *)
      echo "unknown arg: $arg" >&2
      echo "usage: ./scripts/build.sh [--install-only]" >&2
      exit 2
      ;;
  esac
done

command -v xcodegen >/dev/null || { echo "install XcodeGen: brew install xcodegen" >&2; exit 1; }
cd "$ROOT"
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -scheme GLTFInspector -destination 'platform=macOS' \
  -derivedDataPath /tmp/GLTFInspector-dd build
rm -rf "$APP"
cp -R "/tmp/GLTFInspector-dd/Build/Products/Debug/glTF Inspector.app" "$APP"
rm -rf "$APP/Contents/PlugIns/GLTFInspectorTests.xctest"
qlmanage -r

if (( INSTALL_ONLY )); then
  exit 0
fi

open "$APP"
sleep 2
exec "$ROOT/scripts/verify.sh"
