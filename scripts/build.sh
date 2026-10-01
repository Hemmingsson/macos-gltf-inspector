#!/usr/bin/env bash
# Generate, build, and install "glTF Inspector.app", then check plugins.
#
#   ./scripts/build.sh              # install + open /Applications + verify (main checkout only)
#   ./scripts/build.sh --install-only   # install only (no open/verify)
#   ./scripts/verify.sh             # check only (no rebuild)
#   ./scripts/proof.sh              # still-renderer PNG (--qlmanage: + timed qlmanage)
#
# Prefer ./scripts/dev.sh for day-to-day work (worktree-aware, no surprise open).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_ONLY=0

for arg in "$@"; do
  case "$arg" in
    -h|--help)
      sed -n '2,9p' "$0"
      exit 0
      ;;
    --install-only)
      INSTALL_ONLY=1
      ;;
    *)
      echo "unknown arg: $arg" >&2
      echo "usage: ./scripts/build.sh [--install-only]" >&2
      exit 2
      ;;
  esac
done

source "$ROOT/scripts/lib/dev-env.sh"
# A worktree install writes only .build/, so the ship check would open and verify a stale
# /Applications app from another checkout.
if [[ "$INSTALL_KIND" == "worktree" ]] && (( ! INSTALL_ONLY )); then
  echo "build.sh ship check is main-checkout only (it opens $SYSTEM_APP)." >&2
  echo "in a worktree: ./scripts/dev.sh install, then open \"$LOCAL_APP\"" >&2
  exit 1
fi

"$ROOT/scripts/dev.sh" install

if (( INSTALL_ONLY )); then
  exit 0
fi

open "$SYSTEM_APP"
sleep 2
exec "$ROOT/scripts/verify.sh"
