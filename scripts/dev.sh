#!/usr/bin/env bash
# Dev entry point — build, install, run, debug, logs. Never opens the app unless you ask.
#
#   ./scripts/dev.sh build
#   ./scripts/dev.sh install              # → .build/glTF Inspector.app (+ /Applications on main)
#   ./scripts/dev.sh test [-only-testing:…]  # xcodebuild test into this branch's DerivedData
#   ./scripts/dev.sh uitest [-only-testing:…] # opt-in XCUITest flows (steals focus) → .build/uitest.xcresult
#   ./scripts/dev.sh run [fixture]        # install + launch fixture (default: cube)
#   ./scripts/dev.sh logs                 # tail .build/logs/debug.log (or unified log stream)
#   ./scripts/dev.sh fixtures             # list fixture ids
#   ./scripts/dev.sh fixture-path <id>    # resolve absolute path (for launch/tasks)
#   ./scripts/dev.sh app-path             # Mach-O inside .build app (for launch.json)
#   ./scripts/dev.sh catalog [-page id]   # build DesignCatalog + launch in background (open -g)
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/lib/dev-env.sh"

DEFAULT_FIXTURE=cube

usage() {
  sed -n '2,13p' "$0"
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

# The opt-in perf bench (`dev.sh bench`) is left out entirely, not just skipped, so the test
# count stays the suite's own.
dev_test() {
  require_xcodegen
  cd "$ROOT"
  xcodegen generate
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
    xcodebuild -scheme GLTFInspector -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" test -skip-testing:GLTFInspectorTests/PerfBench "$@"
}

# Real-window XCUITest flows (separate scheme, never part of `test`). Takes focus while it runs.
dev_uitest() {
  require_xcodegen
  cd "$ROOT"
  xcodegen generate
  local result="$ROOT/.build/uitest.xcresult"
  mkdir -p "$ROOT/.build"
  rm -rf "$result"
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
    xcodebuild -scheme GLTFInspectorUITests -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" -resultBundlePath "$result" test "$@"
}

# Copy the built app as signed. After a `dev.sh test` the hosted GLTFInspectorTests.xctest is
# inside the app's seal, so it stays: deleting it breaks `codesign --verify`.
install_app() {
  local dst="$1"
  rm -rf "$dst"
  cp -R "$BUILD_PRODUCT" "$dst"
  codesign --verify --deep --strict "$dst" || {
    echo "codesign verify failed: $dst" >&2
    exit 1
  }
}

dev_install() {
  dev_build
  mkdir -p "$ROOT/.build"
  install_app "$LOCAL_APP"

  if [[ "$INSTALL_KIND" == "main" ]]; then
    install_app "$SYSTEM_APP"
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

# DesignCatalog: build into this branch's DerivedData and launch without taking focus.
# Relaunches (quits only this build's catalog process) so the new build and any args apply.
# Args pass through to the app, e.g. `-page colors -appearance dark`.
dev_catalog() {
  require_xcodegen
  cd "$ROOT"
  xcodegen generate
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
    xcodebuild -scheme DesignCatalog -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" build
  # Process path is /private/tmp/... even when CATALOG_APP is /tmp/...
  pkill -f "DesignCatalog.app/Contents/MacOS/DesignCatalog" 2>/dev/null || true
  echo "launch $CATALOG_APP"
  open -g "$CATALOG_APP" --args "$@"
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
  test)
    dev_test "$@"
    ;;
  uitest)
    dev_uitest "$@"
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
  catalog)
    dev_catalog "$@"
    ;;
  bench)
    # Opt-in perf bench (`PerfBench` suites, GLTF_BENCH=1): a table on stdout and in
    # .build/bench/<stamp>.txt (raw xcodebuild log beside it). GLTF_BENCH_RUNS=N (default 3).
    # Wall-clock numbers — run on an idle machine, never alongside another build.
    require_xcodegen
    cd "$ROOT"
    xcodegen generate
    mkdir -p "$ROOT/.build/bench"
    stamp="$(date +%Y%m%d-%H%M%S)"
    raw="$ROOT/.build/bench/$stamp.log"
    table="$ROOT/.build/bench/$stamp.txt"
    status=0
    TEST_RUNNER_GLTF_BENCH=1 TEST_RUNNER_GLTF_BENCH_RUNS="${GLTF_BENCH_RUNS:-3}" \
      DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
      xcodebuild -scheme GLTFInspector -destination 'platform=macOS' \
      -derivedDataPath "$DERIVED_DATA" test -only-testing:GLTFInspectorTests/PerfBench "$@" \
      >"$raw" 2>&1 || status=$?
    {
      echo "# bench $stamp $(git rev-parse --short HEAD) runs=${GLTF_BENCH_RUNS:-3} load=$(sysctl -n vm.loadavg)"
      grep -E '^bench[|]' "$raw" | awk -F'|' '
        BEGIN { printf "%-13s %-14s %-24s %9s %13s %4s\n", "section", "file", "metric (ms)", "median", "spread", "n" }
        { printf "%-13s %-14s %-24s %9s %13s %4s\n", $2, $3, $4, $5, $6, $7 }'
      grep -E '^bench SKIP' "$raw" | sort -u || true
    } | tee "$table"
    if [[ $status -ne 0 ]]; then
      grep -E "error|failed|Issue recorded" "$raw" | tail -20 >&2
      echo "bench failed ($status): $raw" >&2
      exit "$status"
    fi
    echo "wrote $table"
    ;;
  *)
    echo "unknown command: $cmd" >&2
    usage >&2
    exit 2
    ;;
esac
