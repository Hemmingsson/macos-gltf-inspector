#!/usr/bin/env bash
# Bake README assets from ICON.icon and the promo turntables.
#
#   ./scripts/publish.sh             # icon PNG + GIFs → assets/
#   ./scripts/publish.sh --icon-only # ICON.icon → assets/icon.png
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICON="$ROOT/assets/ICON.icon"
PNG="$ROOT/assets/icon.png"
ICON_ONLY=0
if [[ -n "${DEVELOPER_DIR:-}" ]]; then
  ICTOOL="$(dirname "$(dirname "$DEVELOPER_DIR")")/Applications/Icon Composer.app/Contents/Executables/ictool"
else
  ICTOOL="/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
fi
RAW="/tmp/glb-icon-raw.png"

for arg in "$@"; do
  case "$arg" in
    --icon-only) ICON_ONLY=1 ;;
    -h|--help)
      sed -n '2,6p' "$0"
      exit 0
      ;;
    *)
      echo "unknown arg: $arg" >&2
      exit 2
      ;;
  esac
done

[[ -x "$ICTOOL" ]] || { echo "ictool not found — needs Xcode with Icon Composer" >&2; exit 1; }
[[ -d "$ICON" ]] || { echo "missing $ICON" >&2; exit 1; }
command -v ffmpeg >/dev/null || { echo "install ffmpeg: brew install ffmpeg" >&2; exit 1; }

"$ICTOOL" "$ICON" --export-image --output-file "$RAW" \
  --platform macOS --rendition Default --width 512 --height 512 --scale 2 >/dev/null
ffmpeg -y -hide_banner -loglevel error -i "$RAW" -vf 'scale=512:512:flags=lanczos' -pix_fmt rgba "$PNG"
rm -f "$RAW"
echo "ok $PNG"

if [[ "$ICON_ONLY" -eq 0 ]]; then
  "$ROOT/scripts/promo-gif.sh"
fi
