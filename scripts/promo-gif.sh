#!/usr/bin/env bash
# Offscreen 360° GIF of DamagedHelmet for the README. No host window.
#
#   ./scripts/promo-gif.sh
set -euo pipefail

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODEL="$ROOT/screenshots/DamagedHelmet.glb"
FRAMES="/tmp/glb-promo-frames"
BASE="$ROOT/screenshots/base-image.png"
GIF="$ROOT/screenshots/preview.gif"
DD="/tmp/GLBPromo-dd"

command -v xcodegen >/dev/null || { echo "install XcodeGen: brew install xcodegen" >&2; exit 1; }
command -v ffmpeg >/dev/null || { echo "install ffmpeg: brew install ffmpeg" >&2; exit 1; }
[[ -f "$MODEL" ]] || { echo "missing $MODEL" >&2; exit 1; }
[[ -f "$BASE" ]] || { echo "missing $BASE" >&2; exit 1; }

cd "$ROOT"
xcodegen generate
xcodebuild -scheme GLBPromo -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DD" ONLY_ACTIVE_ARCH=YES build

PROMO="$DD/Build/Products/Release/GLBPromo"
export DYLD_FRAMEWORK_PATH="$DD/Build/Products/Release"
rm -rf "$FRAMES"
mkdir -p "$FRAMES"
"$PROMO" --model "$MODEL" --out-dir "$FRAMES" --frames 72 --width 960 --height 540

python3 "$ROOT/scripts/compose-finder-gif.py" --base "$BASE" --frames "$FRAMES" --fps 24 --scale-width 1271 --out "$GIF"

# Quick Look tree spin onto screenshots/quick-look.png
QL_MODEL="$ROOT/screenshots/american_tree.glb"
QL_BASE="$ROOT/screenshots/quick-look.png"
QL_GIF="$ROOT/screenshots/quick-look.gif"
QL_FRAMES="/tmp/glb-promo-tree-frames"
if [[ -f "$QL_MODEL" && -f "$QL_BASE" ]]; then
  rm -rf "$QL_FRAMES"
  mkdir -p "$QL_FRAMES"
  "$PROMO" --model "$QL_MODEL" --out-dir "$QL_FRAMES" --frames 72 --width 1558 --height 984 \
    --aspect 1.583 --padding 1.08
  python3 "$ROOT/scripts/compose-finder-gif.py" --base "$QL_BASE" --frames "$QL_FRAMES" \
    --fps 24 --pane white --out "$QL_GIF"
  echo "ok $QL_GIF"
fi

echo "ok $GIF"
