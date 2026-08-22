#!/usr/bin/env bash
# Fail-fast if a second load-bench starts while bench.lock exists.
# Supports Cursor beforeShellExecution and Claude Code PreToolUse (Bash).
set -euo pipefail

input=$(cat)
out=$(LOAD_BENCH_HOOK_INPUT="$input" python3 - <<'PY'
import json, os, re

raw = os.environ.get("LOAD_BENCH_HOOK_INPUT", "")
try:
    data = json.loads(raw) if raw else {}
except json.JSONDecodeError:
    data = {}

# Cursor: {"command": "..."}; Claude: {"tool_input": {"command": "..."}}
cmd = data.get("command") or ""
tool_input = data.get("tool_input")
if isinstance(tool_input, dict):
    cmd = tool_input.get("command") or cmd

is_claude = data.get("hook_event_name") == "PreToolUse" or isinstance(tool_input, dict)
is_bench = bool(
    re.search(r"(?:^|/|[\s=])(?:scripts/)?load-bench\.sh", cmd)
    or re.search(r"LoadTimeBenchTests", cmd)
)
lock = "/tmp/glb-preview-load-bench/bench.lock"
blocked = is_bench and os.path.isdir(lock)

msg = (
    "load-bench already running (lock at /tmp/glb-preview-load-bench/bench.lock). "
    "Wait for the Benchmarker to finish."
)
agent_msg = (
    "Denied parallel load-bench. Only one Benchmarker may run scripts/load-bench.sh "
    "or LoadTimeBenchTests at a time. Retry after the lock directory is gone."
)

if is_claude:
    if blocked:
        print(json.dumps({
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": msg,
            },
            "systemMessage": agent_msg,
        }))
    else:
        print(json.dumps({
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "allow",
            }
        }))
elif blocked:
    print(json.dumps({
        "permission": "deny",
        "user_message": msg,
        "agent_message": agent_msg,
    }))
else:
    print(json.dumps({"permission": "allow"}))
PY
)
echo "$out"
exit 0
