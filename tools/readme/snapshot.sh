#!/usr/bin/env bash
# Real app capture on the blue Tahoe wallpaper.
# Debug: ./tools/readme/snapshot.sh <fixture> [wallpaper|-]
# Release: RELEASE_APP=/absolute/exported.app ./tools/readme/snapshot.sh (already open and ready).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/readme assets/readme
# "-" explicitly selects the built-in gradient; never silently replace the wallpaper.
WALLPAPER="${2:-${SCREENSHOT_WALLPAPER:-$PWD/.build/readme/tahoe-dark.jpg}}"
if [[ "$WALLPAPER" != "-" && ! -f "$WALLPAPER" ]]; then
    if [[ -n "${2:-${SCREENSHOT_WALLPAPER:-}}" ]]; then
        echo "Wallpaper not found: $WALLPAPER" >&2
        exit 1
    fi
    curl --fail --location --silent --show-error \
        'https://9to5mac.com/wp-content/uploads/sites/6/2025/06/macOS_26_Dark.jpg' \
        -o "$WALLPAPER"
fi
swiftc tools/readme/capture.swift -o .build/readme/capture
if [[ -n "${RELEASE_APP:-}" ]]; then
    # Capture an already opened, verified Release document. Never build, install, or
    # launch a different bundle here. The release workflow verifies ready logs first.
    CAPTURE_APP="$(cd "$RELEASE_APP" && pwd -P)"
    [[ -f "$CAPTURE_APP/Contents/Info.plist" ]] || { echo "Invalid RELEASE_APP bundle" >&2; exit 1; }
else
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
fi
WINDOW_ID="$(.build/readme/capture window "$CAPTURE_APP")"
if ! screencapture -x -l "$WINDOW_ID" .build/readme/window.png; then
    echo "Window capture failed. Check Screen Recording permission for your terminal in System Settings." >&2
    exit 1
fi
.build/readme/capture compose .build/readme/window.png "$WALLPAPER" assets/readme/screenshot.png
printf 'Saved assets/readme/screenshot.png\n'
