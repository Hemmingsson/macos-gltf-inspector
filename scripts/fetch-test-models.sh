#!/usr/bin/env bash
# Download a curated native/testing set of Khronos glTF Sample Assets (GLB only).
# Opt-in. Not called from verify.sh.
#
#   ./scripts/fetch-test-models.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/TestModels/Khronos samples"
# Pin: KhronosGroup/glTF-Sample-Assets main as of this script.
SHA="${KHRONOS_SAMPLE_SHA:-e3cc9d8fee3ab25e21aafdcedda6558f224afbee}"
BASE="https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/${SHA}/Models"
MIN_BYTES=400

# name -> relative path under Models/
MODELS=(
  "BoxVertexColors:BoxVertexColors/glTF-Binary/BoxVertexColors.glb"
  "BoxInterleaved:BoxInterleaved/glTF-Binary/BoxInterleaved.glb"
  "BoomBox:BoomBox/glTF-Binary/BoomBox.glb"
  "Avocado:Avocado/glTF-Binary/Avocado.glb"
  "BarramundiFish:BarramundiFish/glTF-Binary/BarramundiFish.glb"
  "Corset:Corset/glTF-Binary/Corset.glb"
  "AlphaBlendModeTest:AlphaBlendModeTest/glTF-Binary/AlphaBlendModeTest.glb"
  "InterpolationTest:InterpolationTest/glTF-Binary/InterpolationTest.glb"
  "AnimatedMorphCube:AnimatedMorphCube/glTF-Binary/AnimatedMorphCube.glb"
  "ClearCoatTest:ClearCoatTest/glTF-Binary/ClearCoatTest.glb"
  "EmissiveStrengthTest:EmissiveStrengthTest/glTF-Binary/EmissiveStrengthTest.glb"
  "MetalRoughSpheresNoTextures:MetalRoughSpheresNoTextures/glTF-Binary/MetalRoughSpheresNoTextures.glb"
)

mkdir -p "$DEST"

download() {
  local name="$1"
  local rel="$2"
  local dir="$DEST/$name"
  local out="$dir/${name}.glb"
  mkdir -p "$dir"
  if [[ -f "$out" ]]; then
    local existing
    existing="$(wc -c < "$out" | tr -d ' ')"
    if [[ "$existing" -ge "$MIN_BYTES" ]]; then
      echo "skip ${name}.glb (${existing} bytes)"
      return 0
    fi
  fi
  echo "Fetching ${name}.glb"
  if ! curl -fsSL "${BASE}/${rel}" -o "$out"; then
    echo "warn: skip ${name} (not at ${SHA})" >&2
    rm -f "$out"
    return 0
  fi
  local bytes
  bytes="$(wc -c < "$out" | tr -d ' ')"
  if [ "$bytes" -lt "$MIN_BYTES" ]; then
    echo "error: ${out} is ${bytes} bytes (likely an LFS stub); need >= ${MIN_BYTES}" >&2
    rm -f "$out"
    exit 1
  fi
}

for spec in "${MODELS[@]}"; do
  download "${spec%%:*}" "${spec#*:}"
done

echo "Khronos samples in $DEST"
