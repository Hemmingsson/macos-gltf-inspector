#!/usr/bin/env bash
# Release-archive GLBPreview, notarize, staple, zip.
#
#   ./scripts/archive.sh
#   ./scripts/archive.sh --help
#   ./scripts/archive.sh --preflight
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=sparkle-lib.sh
source "$SCRIPT_DIR/sparkle-lib.sh"

ARCHIVE_DIR="${ARCHIVE_DIR:-$ROOT/dist/archive}"
EXPORT_DIR="${EXPORT_DIR:-$ROOT/dist/export}"
DD="${DERIVED_DATA:-$ROOT/dist/DerivedData}"
EXPORT_OPTIONS="$ROOT/scripts/ExportOptions-DeveloperID.plist"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

usage() {
  cat <<'EOF'
Release-archive GLBPreview, notarize, staple, zip.

  ./scripts/archive.sh
  ./scripts/archive.sh --help
  ./scripts/archive.sh --preflight
  NOTARY_PROFILE=glb-preview-notary ./scripts/archive.sh

Environment:
  DERIVED_DATA     default: <repo>/dist/DerivedData
  ARCHIVE_DIR      default: <repo>/dist/archive
  EXPORT_DIR       default: <repo>/dist/export
  NOTARY_PROFILE   default: glb-preview-notary
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
      echo "usage: ./scripts/archive.sh [--help|--preflight]" >&2
      exit 2
      ;;
  esac
done

has_developer_id() {
  security find-identity -v -p codesigning 2>/dev/null \
    | grep -E -q "Developer ID Application.*${TEAM_ID}"
}

has_notary_profile() {
  xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1
}

print_pipeline() {
  echo "would:"
  echo "  1. parse MARKETING_VERSION=$MARKETING CURRENT_PROJECT_VERSION=$BUILD from project.yml"
  echo "  2. xcodegen generate"
  echo "  3. xcodebuild archive Release generic/platform=macOS"
  echo "     derivedData: $DD"
  echo "     archive: $ARCHIVE_DIR/GLBPreview.xcarchive"
  echo "  4. xcodebuild -exportArchive ($EXPORT_OPTIONS) -> $EXPORT_DIR"
  echo "  5. strip GLBPreviewTests.xctest if present"
  echo "  6. codesign --deep --verify --strict"
  echo "  7. assert PreviewExtension.appex, ThumbnailExtension.appex, Sparkle.framework"
  echo "  8. ditto -c -k --keepParent -> $ZIP"
  echo "  9. notarytool submit --keychain-profile $NOTARY_PROFILE --wait"
  echo "  10. stapler staple, re-zip, spctl assess"
  echo "  11. print zip path"
}

cd "$ROOT"
command -v xcodegen >/dev/null || { echo "install XcodeGen: brew install xcodegen" >&2; exit 1; }
parse_project_versions || exit 1

if [[ "$PREFLIGHT" -eq 1 ]]; then
  echo "preflight GLBPreview ${MARKETING} (${BUILD})"
  echo
  echo "tools:"
  tool_status xcodegen
  tool_status python3
  tool_status xcodebuild
  tool_status xcrun
  tool_status codesign
  tool_status ditto
  tool_status stapler
  tool_status spctl
  tool_status plutil
  if command -v xcrun >/dev/null && xcrun --find notarytool >/dev/null 2>&1; then
    echo "  notarytool: ok"
  else
    echo "  notarytool: missing"
  fi
  if [[ -f "$EXPORT_OPTIONS" ]]; then
    echo "  export options: $EXPORT_OPTIONS"
  else
    echo "missing $EXPORT_OPTIONS" >&2
    exit 1
  fi
  echo
  print_pipeline
  echo

  echo "blocked: Developer ID / notary"
  if has_developer_id; then
    echo "  Developer ID Application: present (team $TEAM_ID)"
  else
    echo "  Developer ID Application: missing (install Developer ID Application for team $TEAM_ID)"
  fi
  if has_notary_profile; then
    echo "  notary profile '$NOTARY_PROFILE': present"
  else
    echo "  notary profile '$NOTARY_PROFILE': missing (xcrun notarytool store-credentials $NOTARY_PROFILE --team-id $TEAM_ID)"
  fi
  exit 0
fi

if [[ ! -f "$EXPORT_OPTIONS" ]]; then
  echo "missing $EXPORT_OPTIONS" >&2
  exit 1
fi
if ! has_developer_id; then
  echo "missing Developer ID Application identity (team $TEAM_ID). Install the cert before archiving." >&2
  exit 1
fi
if ! has_notary_profile; then
  echo "missing notary keychain profile '$NOTARY_PROFILE'. Store it with notarytool before submit." >&2
  exit 1
fi

echo "archiving GLBPreview ${MARKETING} (${BUILD})"
xcodegen generate
rm -rf "$ARCHIVE_DIR" "$EXPORT_DIR"
mkdir -p "$ARCHIVE_DIR" "$EXPORT_DIR" "$ROOT/dist"

xcodebuild -scheme GLBPreview -destination 'generic/platform=macOS' \
  -configuration Release \
  -derivedDataPath "$DD" \
  -archivePath "$ARCHIVE_DIR/GLBPreview.xcarchive" \
  archive

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_DIR/GLBPreview.xcarchive" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS"

APP="$EXPORT_DIR/GLBPreview.app"
[[ -d "$APP" ]] || { echo "missing exported $APP" >&2; exit 1; }

rm -rf "$APP/Contents/PlugIns/GLBPreviewTests.xctest"

codesign --deep --verify --strict "$APP"
test -d "$APP/Contents/PlugIns/PreviewExtension.appex"
test -d "$APP/Contents/PlugIns/ThumbnailExtension.appex"
test -d "$APP/Contents/Frameworks/Sparkle.framework"

rm -f "$ZIP"
zip_exported_app "$EXPORT_DIR" "$ZIP"

xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
rm -f "$ZIP"
zip_exported_app "$EXPORT_DIR" "$ZIP"

spctl --assess --type execute "$APP"
echo "ok $ZIP"
echo "$ZIP"
