#!/usr/bin/env bash
# Developer ID archive, Sparkle appcast, and GitHub release.
#
#   ./scripts/release.sh
#   ./scripts/release.sh --help
#   ./scripts/release.sh --preflight
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=sparkle-lib.sh
source "$SCRIPT_DIR/sparkle-lib.sh"

ARCHIVE_SH="$ROOT/scripts/archive.sh"
APPCAST_SH="$ROOT/scripts/appcast.sh"

usage() {
  cat <<'EOF'
Developer ID archive, Sparkle appcast, and GitHub release.

  ./scripts/release.sh
  ./scripts/release.sh --help
  ./scripts/release.sh --preflight

Full run calls archive.sh, appcast.sh, then gh release create.
EOF
}

PREFLIGHT=0
for arg in "$@"; do
  case "$arg" in
    -h|--help)
      usage
      exit 0
      ;;
    --preflight)
      PREFLIGHT=1
      ;;
    *)
      echo "unknown arg: $arg" >&2
      echo "usage: ./scripts/release.sh [--help|--preflight]" >&2
      exit 2
      ;;
  esac
done

script_status() {
  if [[ -f "$1" ]]; then
    echo "  $2: ok"
    return 0
  fi
  echo "  $2: missing"
  return 1
}

print_pipeline() {
  echo "would:"
  echo "  1. require gh and gh auth"
  echo "  2. parse MARKETING_VERSION=${MARKETING:-?} CURRENT_PROJECT_VERSION=${BUILD:-?} from project.yml"
  echo "  3. TAG=${TAG:-v?}"
  echo "  4. fail if gh release view ${TAG:-v?} --repo $GH_REPO already exists"
  echo "  5. refuse the placeholder Sparkle public key"
  echo "  6. ./scripts/archive.sh"
  echo "  7. ./scripts/appcast.sh $ZIP"
  echo "  8. collect zip, notes.md if present, dist/appcast.xml, dist/updates/*.delta"
  echo "  9. gh release create ${TAG:-v?} (notes file or Build ${BUILD:-?}. )"
  echo "  10. also upload zip as GLBPreview.zip (stable latest download name)"
  echo "  11. print release URL and $FEED_URL"
}

report_gh() {
  echo "gh:"
  if ! command -v gh >/dev/null; then
    echo "  auth: skipped (gh missing)"
    echo "  release: skipped (gh missing)"
    return
  fi
  if ! gh auth status >/dev/null 2>&1; then
    echo "  auth: missing (gh auth login)"
    echo "  release: skipped (not authenticated)"
    return
  fi
  echo "  auth: ok"
  if [[ -z "${TAG:-}" ]]; then
    echo "  release: skipped (no tag)"
    return
  fi
  if gh release view "$TAG" --repo "$GH_REPO" >/dev/null 2>&1; then
    echo "  release $TAG: already exists (full run would fail)"
  else
    echo "  release $TAG: not found (ok to create)"
  fi
}

cd "$ROOT"

if [[ "$PREFLIGHT" -eq 1 ]]; then
  scripts_ok=1
  echo "preflight release"
  echo
  echo "scripts:"
  script_status "$ARCHIVE_SH" "archive.sh" || scripts_ok=0
  script_status "$APPCAST_SH" "appcast.sh" || scripts_ok=0
  echo
  echo "tools:"
  tool_status gh
  tool_status xcodegen
  tool_status python3
  echo

  if uses_placeholder_ed_key; then
    echo "warning: GLBUpdateConfig/project.yml still uses the placeholder Sparkle public key" >&2
  fi
  echo

  if parse_project_versions; then
    echo "versions: MARKETING_VERSION=$MARKETING CURRENT_PROJECT_VERSION=$BUILD TAG=$TAG"
  else
    MARKETING="" BUILD="" TAG="" ZIP="" NOTES=""
    echo "versions: could not parse project.yml"
  fi
  echo

  report_gh
  echo

  if [[ -f "$ARCHIVE_SH" ]] && command -v xcodegen >/dev/null && command -v python3 >/dev/null; then
    echo "archive.sh --preflight:"
    "$ARCHIVE_SH" --preflight
    echo
  else
    echo "archive.sh --preflight: skipped (need archive.sh, xcodegen, python3)"
    echo
  fi

  print_pipeline
  echo

  if [[ "$scripts_ok" -eq 0 ]]; then
    echo "missing archive.sh or appcast.sh" >&2
    exit 1
  fi
  exit 0
fi

[[ -f "$ARCHIVE_SH" ]] || { echo "missing $ARCHIVE_SH" >&2; exit 1; }
[[ -f "$APPCAST_SH" ]] || { echo "missing $APPCAST_SH" >&2; exit 1; }
command -v gh >/dev/null || { echo "missing gh (brew install gh)" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "gh is not authenticated (gh auth login)" >&2; exit 1; }

parse_project_versions || exit 1
require_newer_build || exit 1

if uses_placeholder_ed_key; then
  echo "refusing to publish with the placeholder Sparkle public key. Run generate_keys and paste SUPublicEDKey into project.yml and GLBUpdateConfig.publicEdKey." >&2
  exit 1
fi

if gh release view "$TAG" --repo "$GH_REPO" >/dev/null 2>&1; then
  echo "release $TAG already exists on $GH_REPO" >&2
  exit 1
fi

echo "releasing GLB Preview ${MARKETING} (${BUILD}) as $TAG"
"$ARCHIVE_SH"
"$APPCAST_SH" "$ZIP"

[[ -f "$ZIP" ]] || { echo "missing $ZIP" >&2; exit 1; }
[[ -f "$ROOT/dist/appcast.xml" ]] || { echo "missing $ROOT/dist/appcast.xml" >&2; exit 1; }

assets=("$ZIP" "$ROOT/dist/appcast.xml")
if [[ -f "$NOTES" ]]; then
  assets+=("$NOTES")
fi
shopt -s nullglob
assets+=("$ROOT/dist/updates"/*.delta)
shopt -u nullglob

create_args=(release create "$TAG" --repo "$GH_REPO" --title "GLB Preview ${MARKETING}")
if [[ -f "$NOTES" ]]; then
  create_args+=(--notes-file "$NOTES")
else
  create_args+=(--notes "Build ${BUILD}.")
fi
create_args+=("${assets[@]}")

gh "${create_args[@]}"

# Stable name so README's latest zip link keeps working.
cp "$ZIP" "$ROOT/dist/GLBPreview.zip"
gh release upload "$TAG" "$ROOT/dist/GLBPreview.zip" --repo "$GH_REPO" --clobber

echo "ok https://github.com/${GH_REPO}/releases/tag/${TAG}"
echo "feed $FEED_URL"
