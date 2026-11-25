#!/usr/bin/env bash
# Real app capture + wallpaper. First argument is a fixture ID; optional second is wallpaper.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/demo docs/media
WALLPAPER="${2:-${SCREENSHOT_WALLPAPER:-$PWD/.build/demo/tahoe-dark.jpg}}"
if [[ ! -f "$WALLPAPER" ]]; then
    if [[ -n "${2:-${SCREENSHOT_WALLPAPER:-}}" ]]; then
        echo "Wallpaper not found: $WALLPAPER" >&2
        exit 1
    fi
    curl --fail --location --silent --show-error \
        'https://9to5mac.com/wp-content/uploads/sites/6/2025/06/macOS_26_Dark.jpg' \
        -o "$WALLPAPER"
fi
swiftc demo/capture.swift -o .build/demo/capture
./scripts/dev.sh run "${1:-cube}"
python3 - <<'PY'
import pathlib, time
log = pathlib.Path('.build/logs/debug.log')
for _ in range(120):
    text = log.read_text() if log.exists() else ''
    if 'open failed' in text or 'canvas failed' in text:
        raise SystemExit('Fixture failed to load; see .build/logs/debug.log')
    if 'canvas ready' in text and 'open ready' in text:
        break
    time.sleep(0.5)
else:
    raise SystemExit('Timed out waiting for canvas ready')
PY
source scripts/lib/dev-env.sh
CAPTURE_APP="$LOCAL_APP"
WINDOW_ID="$(.build/demo/capture window "$CAPTURE_APP")"
if ! screencapture -x -l "$WINDOW_ID" .build/demo/window.png; then
    echo "Window capture failed. Check Screen Recording permission for your terminal in System Settings." >&2
    exit 1
fi
.build/demo/capture compose .build/demo/window.png "$WALLPAPER" docs/media/screenshot.png
printf 'Saved docs/media/screenshot.png\n'
