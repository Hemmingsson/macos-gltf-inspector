#!/usr/bin/env bash
# Dev entry point — build, install, run, debug, logs. Never opens the app unless you ask.
#
#   ./scripts/dev.sh build
#   ./scripts/dev.sh install              # → .build/glTF Inspector.app (+ /Applications on main)
#   ./scripts/dev.sh run [fixture]        # install + launch fixture (default: cube)
#   ./scripts/dev.sh logs                 # tail .build/logs/debug.log (or unified log stream)
#   ./scripts/dev.sh fixtures             # list fixture ids
#   ./scripts/dev.sh fixture-path <id>    # resolve absolute path (for launch/tasks)
#   ./scripts/dev.sh app-path             # Mach-O inside .build app (for launch.json)
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/lib/dev-env.sh"

DEFAULT_FIXTURE=cube

usage() {
  sed -n '2,12p' "$0"
}

require_xcodegen() {
  command -v xcodegen >/dev/null || {
    echo "install XcodeGen: brew install xcodegen" >&2
    exit 1
  }
}

dev_build() {
  require_xcodegen
  cd "$ROOT"
  xcodegen generate
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
    xcodebuild -scheme GLTFInspector -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" build
}

dev_install() {
  dev_build
  mkdir -p "$ROOT/.build"
  rm -rf "$LOCAL_APP"
  cp -R "$BUILD_PRODUCT" "$LOCAL_APP"
  rm -rf "$LOCAL_APP/Contents/PlugIns/GLTFInspectorTests.xctest"

  if [[ "$INSTALL_KIND" == "main" ]]; then
    rm -rf "$SYSTEM_APP"
    cp -R "$BUILD_PRODUCT" "$SYSTEM_APP"
    rm -rf "$SYSTEM_APP/Contents/PlugIns/GLTFInspectorTests.xctest"
    qlmanage -r
  fi

  echo "installed $LOCAL_APP"
  if [[ "$INSTALL_KIND" == "main" ]]; then
    echo "installed $SYSTEM_APP"
  fi
}

dev_run() {
  local fixture="${1:-$DEFAULT_FIXTURE}"
  local model
  model="$(dev_fixture_path "$fixture")"
  if [[ ! -e "$model" ]]; then
    echo "missing fixture file: $model" >&2
    exit 1
  fi

  dev_install
  mkdir -p "$LOG_DIR" "$(dirname "$LOCAL_APP")"
  : >"$LOG_FILE"
  cat >"$(dirname "$LOCAL_APP")/dev-env" <<EOF
GLTF_REPO_ROOT=$ROOT
GLTF_LOG_FILE=$LOG_FILE
GLTF_VERBOSE=1
EOF

  echo "run $fixture → $model"
  echo "log $LOG_FILE"
  # `open` survives VS Code task exit; direct exec + & gets SIGHUP when the task ends.
  open -a "$LOCAL_APP" "$model"
}

dev_logs() {
  mkdir -p "$LOG_DIR"
  if [[ -f "$LOG_FILE" ]]; then
    echo "tailing $LOG_FILE (Ctrl-C to stop)"
    tail -n 200 -f "$LOG_FILE"
    return
  fi

  echo "no $LOG_FILE yet — streaming unified log (Ctrl-C to stop)"
  log stream --style compact --info \
    --predicate 'subsystem == "lol.mattias.gltf-inspector"'
}

dev_fixtures() {
  dev_fixture_ids
}

cmd="${1:-}"
shift || true

case "$cmd" in
  -h|--help|help|"")
    usage
    ;;
  build)
    dev_build
    ;;
  install)
    dev_install
    ;;
  run)
    dev_run "${1:-$DEFAULT_FIXTURE}"
    ;;
  logs)
    dev_logs
    ;;
  fixtures)
    dev_fixtures
    ;;
  fixture-path)
    [[ $# -eq 1 ]] || {
      echo "usage: ./scripts/dev.sh fixture-path <id>" >&2
      exit 2
    }
    dev_fixture_path "$1"
    ;;
  app-path)
    echo "$EXEC"
    ;;
  *)
    echo "unknown command: $cmd" >&2
    usage >&2
    exit 2
    ;;
esac
