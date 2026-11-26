#!/bin/bash
# Render the 15s Metal turntable used by demo-video/index.html.
# Usage: ./demo-video/turntable.sh [path-to.glb]
# Meshopt/quantized AET_Showcase.glb is decoded automatically when needed.
# Encodes all-intra H.264 so HyperFrames frame-seeks stay smooth.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck disable=SC1091
source scripts/lib/dev-env.sh

model="${1:-}"
if [[ -z "$model" ]]; then
  if [[ -f demo-video/AET_Showcase.glb ]]; then
    model="demo-video/AET_Showcase.glb"
  else
    echo "Pass a .glb path, or place a decoded AET_Showcase.glb in demo-video/" >&2
    exit 1
  fi
fi
model="$(cd "$(dirname "$model")" && pwd)/$(basename "$model")"

frameworks="${GLTF_DEMO_FRAMEWORKS:-}"
if [[ -z "$frameworks" || ! -d "$frameworks/Renderer.framework" ]]; then
  if [[ -d "$DERIVED_DATA/Build/Products/Debug/Renderer.framework" ]]; then
    frameworks="$DERIVED_DATA/Build/Products/Debug"
  elif [[ -d "$LOCAL_APP/Contents/Frameworks/Renderer.framework" ]]; then
    frameworks="$LOCAL_APP/Contents/Frameworks"
  else
    xcode_fw="$(ls -d "$HOME"/Library/Developer/Xcode/DerivedData/GLTFInspector-*/Build/Products/Debug/Renderer.framework 2>/dev/null | head -1 || true)"
    if [[ -n "$xcode_fw" ]]; then
      frameworks="$(dirname "$xcode_fw")"
    fi
  fi
fi
if [[ -z "${frameworks:-}" || ! -d "$frameworks/Renderer.framework" ]]; then
  echo "Renderer.framework not found. Run ./scripts/dev.sh install first, or set GLTF_DEMO_FRAMEWORKS." >&2
  exit 1
fi

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

prepared="$model"
python3 - "$model" "$scratch/prepared.glb" <<'PY' || true
import json, struct, subprocess, sys
from pathlib import Path
src, dst = map(Path, sys.argv[1:3])
data = src.read_bytes()
length = struct.unpack_from("<I", data, 12)[0]
js = json.loads(data[20 : 20 + length])
need = set(js.get("extensionsRequired") or [])
if need & {"EXT_meshopt_compression", "KHR_mesh_quantization"}:
    subprocess.check_call(["npx", "--yes", "@gltf-transform/cli", "copy", str(src), str(dst.with_suffix(".decoded.glb"))])
    subprocess.check_call(["npx", "--yes", "@gltf-transform/cli", "dequantize", str(dst.with_suffix(".decoded.glb")), str(dst)])
    print(f"decoded {src.name} → {dst.name}", file=sys.stderr)
else:
    sys.exit(2)
PY
if [[ -f "$scratch/prepared.glb" ]]; then
  prepared="$scratch/prepared.glb"
fi

xcrun swiftc -parse-as-library demo-video/turntable.swift \
  -F "$frameworks" -framework Renderer -framework GLTFCore \
  -Xlinker -rpath -Xlinker "$frameworks" \
  -o "$scratch/turntable"

# All-intra (-g 1 / keyint=1) so HyperFrames can seek every frame without B-frame jitter.
"$scratch/turntable" "$prepared" | ffmpeg -hide_banner -loglevel error \
  -framerate 60 -f image2pipe -c:v png -i - \
  -f lavfi -i color=c=0xeceef0:s=744x668:r=60 \
  -filter_complex "[1:v][0:v]overlay=shortest=1:format=auto,format=yuv420p" \
  -c:v libx264 -crf 14 -g 1 -keyint_min 1 -bf 0 -pix_fmt yuv420p -movflags +faststart \
  "$scratch/turntable.mp4"

mv "$scratch/turntable.mp4" demo-video/turntable.mp4
# Keep a local copy of the rendered AET (or other) model next to the turntable.
cp -f "$prepared" "demo-video/$(basename "$model")"
echo "Wrote demo-video/turntable.mp4 from $(basename "$model")"
