# next-workflow skill map

Instructions live in `.fejk-agents/skills/`. This note is only the map of where each job sits.

| Job | Skill |
| --- | --- |
| Red, green, refactor | `n-tdd` |
| Detached `.worktrees/<id>`, land onto `main` | `n-worktrees` |
| Independent tasks or failures in one message | `n-parallel` |
| Several tasks in this session, no per-task agent | `n-execute` |
| One implementer per task, then a task review | `n-subagents` |
| Pick execute or subagents | `n-build` |
| Fresh output before a pass, fixed, or done claim | `n-verify` |
| Task or epic reviewer | `n-review` |
| One Sol reviewer on the local diff | `n-sol-loop` |
| Prove, Sol, launch, ask, land, complete | `n-full-send` |

Landing is a fast-forward of `main`. There is no pull request. Worktrees are detached. The board is the record. Sol is not replaced by another model. `n-full-send` is the only way a task lands, and only after the user approves the running app.

Cursor and Codex load the skills from `.agents/skills/` (symlinks). Codex scenarios have not been re-run.
