#!/usr/bin/env bash
# Download the Khronos Sample Viewer IBL equirects used by the live app.
# Source: glTF-Sample-Environments `low_resolution_hdrs` (not Git LFS stubs on main).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/assets/ibl/khronos"
BASE="https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Environments/low_resolution_hdrs"
MIN_BYTES=10000

# Stem must match Sample Viewer `fillEnvironmentWithPaths` keys.
STEMS=(
  field
  neutral
  Colorful_Studio
)

mkdir -p "$DEST"

download() {
  local stem="$1"
  local out="$DEST/${stem}.hdr"
  echo "Fetching ${stem}.hdr"
  curl -fsSL "${BASE}/${stem}.hdr" -o "$out"
  local bytes
  bytes="$(wc -c < "$out" | tr -d ' ')"
  if [ "$bytes" -lt "$MIN_BYTES" ]; then
    echo "error: ${out} is ${bytes} bytes (likely an LFS stub); need >= ${MIN_BYTES}" >&2
    rm -f "$out"
    exit 1
  fi
}

for stem in "${STEMS[@]}"; do
  download "$stem"
done

cat > "$DEST/LICENSES.md" <<'EOF'
# Khronos Sample Viewer environments

Equirectangular HDRs vendored from the Khronos
[`glTF-Sample-Environments`](https://github.com/KhronosGroup/glTF-Sample-Environments)
`low_resolution_hdrs` branch — the same files the
[Sample Viewer](https://github.com/KhronosGroup/glTF-Sample-Viewer) loads at runtime.
Do not replace these with Git LFS pointer files from `main`.

| File | Title | SPDX |
|---|---|---|
| `field.hdr` | Field | SPDX-FileCopyrightText: 2020 HDRLabs sampled by UX3D GmbH. Distributed by Khronos Group; SPDX-License-Identifier: CC-BY-NC-SA-3.0 |
| `neutral.hdr` | Studio Neutral | SPDX-FileCopyrightText: 2020 Amazon, LLC. Distributed by Khronos Group; SPDX-License-Identifier: CC-BY-4.0 |
| `Colorful_Studio.hdr` | Colorful Studio | SPDX-FileCopyrightText: 2020 Amazon, LLC. Distributed by Khronos Group; SPDX-License-Identifier: CC-BY-4.0 |

Upstream license sidecar files (where present): `https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Environments/low_resolution_hdrs/<stem>.hdr.license`
EOF

echo "Vendored ${#STEMS[@]} HDRs into $DEST"
