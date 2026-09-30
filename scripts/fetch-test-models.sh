#!/usr/bin/env bash
# Download the pinned Khronos glTF Sample Assets into TestModels/Khronos samples (gitignored).
#
#   ./scripts/fetch-test-models.sh
#
# The sample list is TestModels/References/manifest.json — the same file the pixel-diff
# harness asserts against — so there is exactly one list to keep up to date. Each entry names
# the upstream folder (`source`) and the files to fetch from it (`files`, primary model first);
# the commit is pinned once at the top of the manifest (`samples.commit`).
# Opt-in. Not called from verify.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/TestModels/Khronos samples"
MANIFEST="$ROOT/TestModels/References/manifest.json"

# One "name<TAB>url<TAB>file" line per file to fetch.
LIST="$(python3 - "$MANIFEST" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
s = m["samples"]
base = f"https://raw.githubusercontent.com/{s['repository']}/{s['commit']}"
for e in m["entries"]:
    for f in e["files"]:
        print(f"{e['name']}\t{base}/{e['source']}/{f}\t{f}")
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
