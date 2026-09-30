#!/usr/bin/env bash
# Seed an isolated first-paint / first-frame experiment from the dirty champion tree.
#
#   ./scripts/seed-webkit-fp-exp.sh 011 "skip first-bind generateMipmap"
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAIN="$(cd "$ROOT/../.." && pwd)"
ID="${1:?id like 011}"
NOTE="${2:-experiment}"
BRANCH="exp/wk-ff-${ID}"
DEST="$MAIN/.worktrees/wk-ff-${ID}"

if [[ "$ROOT" != *"/webkit-renderer" ]]; then
  echo "run from the webkit-renderer champion worktree" >&2
  exit 2
fi
if [[ -e "$DEST" ]]; then
  echo "already exists: $DEST" >&2
  exit 2
fi

git -C "$MAIN" worktree add -b "$BRANCH" "$DEST" webkit-renderer
# KEEP work on champion is often uncommitted — the experiment must start from that tree.
rsync -a --delete \
  --exclude .git \
  --exclude .build \
  --exclude GLTFInspector.xcodeproj \
  --exclude .DS_Store \
  "$ROOT/" "$DEST/"
echo "seeded $DEST ($BRANCH) — $NOTE"
echo "implement one change, smoke-build, perf: commit, do not bench"
