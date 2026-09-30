#!/usr/bin/env bash
# Pin and licence record for the vendored Khronos glTF Sample Renderer (RendererWebKit/web-renderer).
#
#   ./scripts/vendor-web-renderer.sh           # check: files match VERSION, notices present
#   ./scripts/vendor-web-renderer.sh record    # after replacing files: rewrite VERSION checksums
#
# The bundle is not rebuilt here: a rebuild needs `npm ci` (rollup, physx-js-webidl, the
# interactivity engine), which this repo does not pull. To update it, on a machine that may:
#
#   git clone https://github.com/KhronosGroup/glTF-Sample-Renderer && cd glTF-Sample-Renderer
#   git checkout <commit>           # then set upstream_commit in VERSION to it
#   npm ci && npx rollup -c         # dist/gltf-viewer.module.js carries a licence banner
#   npx esbuild dist/gltf-viewer.module.js --minify > gltf-viewer.module.js
#   copy dist/libs/* (not physx-js-webidl.wasm) + assets/lut_*.png; keep libs/draco_* (ours)
#   paste the dist banner into THIRD_PARTY_NOTICES.txt section 1, then run `record` and the
#   web pixel diff (./scripts/dev.sh test); goldens must match or be regenerated on purpose.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$ROOT/RendererWebKit/web-renderer"
VERSION="$DIR/VERSION"
FILES=(gltf-viewer.module.js libs/libktx.js libs/libktx.wasm libs/mikktspace.js libs/mikktspace_bg.wasm
  libs/mkkellogg-sort.worker.js libs/sorter_no_simd_non_shared.wasm libs/draco_wasm_wrapper_gltf.js
  libs/draco_decoder_gltf.wasm assets/lut_ggx.png assets/lut_charlie.png assets/lut_sheen_E.png)

checksums() {
  (cd "$DIR" && shasum -a 256 "${FILES[@]}")
}

case "${1:-check}" in
  record)
    tmp="$(mktemp)"
    sed '/^# sha256/,$d' "$VERSION" >"$tmp"
    { echo "# sha256"; checksums; } >>"$tmp"
    mv "$tmp" "$VERSION"
    echo "recorded $(( ${#FILES[@]} )) checksums in $VERSION"
    ;;
  check)
    for f in LICENSE.md LICENSE-draco.txt THIRD_PARTY_NOTICES.txt; do
      [[ -s "$DIR/$f" ]] || { echo "missing $f" >&2; exit 1; }
    done
    grep -q '^upstream_commit=[0-9a-f]\{40\}$' "$VERSION" || { echo "VERSION has no upstream_commit" >&2; exit 1; }
    diff <(sed -n '/^# sha256/,$p' "$VERSION" | tail -n +2) <(checksums) \
      || { echo "web-renderer files differ from VERSION (run 'record' after an intentional update)" >&2; exit 1; }
    echo "web-renderer matches VERSION ($(grep '^upstream_commit=' "$VERSION"))"
    ;;
  *)
    sed -n '2,6p' "$0"
    exit 1
    ;;
esac
