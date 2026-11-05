---
name: n-verify
description: Require fresh command output before any claim that work passes, is fixed, or is done. Use before completing a task, landing, or agreeing that tests passed.
---

# n-verify

A claim needs a command you ran and read after the edit it talks about. An earlier run, or another agent's status line, is not that command.

1. Name the command that would prove the claim.
2. Run it. Read the output, the exit code, and the failure count.
3. Say only what that output shows. When it does not support the claim, report the actual result.

| Claim | Run | Not enough |
| --- | --- | --- |
| Tests pass | The project's suite | A previous run, "should pass" |
| Build succeeds | The build | Lint, or a clean log |
| Bug fixed | The original failure, now passing | The code changed |
| Agent finished | The diff, plus the tests | `Status: DONE` |
| Task done | Each acceptance check, fresh | A green suite for a different task |

A regression test counts after you watched it fail and then pass (`n-tdd`).

UI and runtime behaviour: run the app and look. A green mock does not prove the screen.
