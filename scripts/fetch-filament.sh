#!/usr/bin/env bash
# Google's prebuilt Filament SDK (macOS, arm64) into .build/filament for FilamentBridge.
# Idempotent: does nothing once the libraries are there.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${FILAMENT_VERSION:-v1.80.0}"
SDK="$ROOT/.build/filament"
[[ -f "$SDK/lib/arm64/libfilament.a" ]] && exit 0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl -fL --retry 3 -o "$TMP/filament.tgz" \
  "https://github.com/google/filament/releases/download/$VERSION/filament-$VERSION-mac.tgz"
tar -xzf "$TMP/filament.tgz" -C "$TMP"
mkdir -p "$SDK"
cp -R "$TMP/filament/include" "$TMP/filament/lib" "$TMP/filament/LICENSE" "$SDK/"
echo "Filament $VERSION → $SDK"
