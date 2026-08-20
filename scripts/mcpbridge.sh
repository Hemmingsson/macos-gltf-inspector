#!/bin/bash
# Pin Xcode.app — system xcode-select may point at CommandLineTools (no mcpbridge).
# mcpbridge also requires a live Xcode PID (MCP_XCODE_PID) or it fatals / hangs.
set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
BRIDGE="$DEVELOPER_DIR/usr/bin/mcpbridge"

if [[ ! -x "$BRIDGE" ]]; then
  echo "mcpbridge not found at $BRIDGE" >&2
  exit 1
fi

if [[ -z "${MCP_XCODE_PID:-}" ]]; then
  # Prefer the Xcode that owns this Developer dir.
  MCP_XCODE_PID="$(
    pgrep -x Xcode 2>/dev/null | while read -r pid; do
      exe="$(ps -o comm= -p "$pid" 2>/dev/null || true)"
      if [[ "$exe" == "/Applications/Xcode.app/Contents/MacOS/Xcode" ]]; then
        echo "$pid"
        break
      fi
    done
  )"
  if [[ -z "${MCP_XCODE_PID}" ]]; then
    MCP_XCODE_PID="$(pgrep -nx Xcode 2>/dev/null || true)"
  fi
fi

if [[ -z "${MCP_XCODE_PID:-}" ]]; then
  echo "mcpbridge: open Xcode with GLBPreview.xcodeproj first (no Xcode process found)." >&2
  exit 1
fi

export MCP_XCODE_PID
exec "$BRIDGE" "$@"
