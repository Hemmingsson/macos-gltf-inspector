#!/usr/bin/env bash
# Download Sparkle CLI tools for release/appcast generation.
# This script never creates or stores Sparkle private keys.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPARKLE_VERSION="${SPARKLE_VERSION:-2.9.6}"
TOOLS_DIR="$ROOT/tools/sparkle"
BIN_DIR="$TOOLS_DIR/bin"
VERSION_FILE="$TOOLS_DIR/.version"

if [[ -x "$BIN_DIR/generate_appcast" ]] && [[ -f "$VERSION_FILE" ]] && [[ "$(cat "$VERSION_FILE")" == "$SPARKLE_VERSION" ]]; then
  echo "$BIN_DIR"
  exit 0
fi

command -v curl >/dev/null || { echo "missing curl" >&2; exit 1; }
command -v tar >/dev/null || { echo "missing tar" >&2; exit 1; }
command -v shasum >/dev/null || { echo "missing shasum" >&2; exit 1; }

case "$SPARKLE_VERSION" in
  2.9.6) expected_sha256="52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192" ;;
  *) echo "no verified Sparkle archive hash for version $SPARKLE_VERSION" >&2; exit 1 ;;
esac

tmp="$(mktemp -d "${TMPDIR:-/tmp}/sparkle-tools.XXXXXX")"
cleanup() {
  rm -rf "$tmp"
}
trap cleanup EXIT

download_release() {
  local url="$1"
  local output="$2"

  curl --fail --location --silent --show-error "$url" --output "$output"
}

extract_archive() {
  local archive="$1"
  local dest="$2"

  case "$archive" in
    *.tar.xz|*.txz)
      tar -xJf "$archive" -C "$dest"
      ;;
    *.tar.gz|*.tgz)
      tar -xzf "$archive" -C "$dest"
      ;;
    *.zip)
      command -v ditto >/dev/null || { echo "missing ditto for zip extraction" >&2; exit 1; }
      ditto -x -k "$archive" "$dest"
      ;;
    *)
      echo "unsupported archive: $archive" >&2
      exit 1
      ;;
  esac
}

archive="$tmp/Sparkle-${SPARKLE_VERSION}.tar.xz"
base_url="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}"
download_release "$base_url/$(basename "$archive")" "$archive"
actual_sha256="$(shasum -a 256 "$archive" | awk '{print $1}')"
if [[ "$actual_sha256" != "$expected_sha256" ]]; then
  echo "Sparkle $SPARKLE_VERSION archive checksum mismatch" >&2
  echo "expected: $expected_sha256" >&2
  echo "actual:   $actual_sha256" >&2
  exit 1
fi

extract_dir="$tmp/extracted"
mkdir -p "$extract_dir"
extract_archive "$archive" "$extract_dir"

generate_appcast="$(find "$extract_dir" -type f -name generate_appcast -perm -111 -print -quit)"
if [[ -z "$generate_appcast" ]]; then
  generate_appcast="$(find "$extract_dir" -type f -name generate_appcast -print -quit)"
fi
if [[ -z "$generate_appcast" ]]; then
  echo "Sparkle $SPARKLE_VERSION archive did not contain generate_appcast" >&2
  exit 1
fi

source_bin="$(cd "$(dirname "$generate_appcast")" && pwd)"
rm -rf "$TOOLS_DIR"
mkdir -p "$TOOLS_DIR"
cp -R "$source_bin" "$BIN_DIR"
chmod +x "$BIN_DIR"/*
printf '%s\n' "$SPARKLE_VERSION" > "$VERSION_FILE"

echo "$BIN_DIR"
