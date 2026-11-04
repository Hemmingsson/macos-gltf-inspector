#!/usr/bin/env bash
# Download the pinned Khronos glTF Sample Assets into TestModels/Khronos samples (gitignored).
#
#   ./scripts/fetch-test-models.sh
#
# The sample list is TestModels/References/manifest.json (rest stills) plus
# TestModels/References/Animated/manifest.json (fixed-time poses). Both pin the same
# commit. Each entry names the upstream folder (`source`) and the files to fetch
# (`files`, primary model first). Animated entries use `sample` as the local folder
# so a pose named AnimatedMorphCube-t0.5 reuses the AnimatedMorphCube download.
# Opt-in. Not called from verify.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/TestModels/Khronos samples"
MANIFESTS=(
  "$ROOT/TestModels/References/manifest.json"
  "$ROOT/TestModels/References/Animated/manifest.json"
)

# One "folder<TAB>url<TAB>file" line per file to fetch.
LIST="$(python3 - "${MANIFESTS[@]}" <<'PY'
import json, sys
manifests = [json.load(open(path)) for path in sys.argv[1:]]
pins = {(m["samples"]["repository"], m["samples"]["commit"]) for m in manifests}
if len(pins) != 1:
    raise SystemExit("reference manifests pin different sample commits: " + ", ".join(map(str, pins)))
repository, commit = pins.pop()
base = f"https://raw.githubusercontent.com/{repository}/{commit}"
seen = set()
for manifest in manifests:
    for entry in manifest["entries"]:
        folder = entry.get("sample", entry["name"])
        for filename in entry["files"]:
            key = (folder, filename)
            if key in seen:
                continue
            seen.add(key)
            print(f"{folder}\t{base}/{entry['source']}/{filename}\t{filename}")
PY
)"

while IFS=$'\t' read -r name url file; do
  out="$DEST/$name/$file"
  # Git LFS pointer files are small text stubs; a real asset never starts with this line.
  if [[ -f "$out" ]] && ! head -c 40 "$out" | grep -q "git-lfs"; then
    continue
  fi
  echo "Fetching $name/$file"
  mkdir -p "$(dirname "$out")"
  curl -fsSL "$url" -o "$out"
  if head -c 40 "$out" | grep -q "git-lfs"; then
    echo "error: $out is a Git LFS pointer, not the asset" >&2
    rm -f "$out"
    exit 1
  fi
done <<<"$LIST"

echo "Khronos samples in $DEST"
