---
name: n-execute
description: Build ready tasks yourself in this session, one at a time. Use when the user said no subagents, or the harness cannot dispatch them.
---

# n-execute

You are the implementer in the current checkout. Do not create a worktree. Finish each task before you start the next. Do not ask whether to continue.

For each task:

1. `backlog start <id>`. Something visible changes: send `n-visualizer` (background) for the `before` capture.
2. Read `backlog show <id> --full` again. What you remember is not the task.
3. `n-tdd`, then `n-verify` on that task's checks.
4. `n-review` when you can dispatch a reviewer. When you cannot, apply `n-review`'s receive rules yourself and write `Review: self` on the task.
5. `n-full-send`.

Write `Ruling: what — why — cost if wrong` on the task and keep going. Stop only when the next step is irreversible or destructive, deletes data or leaves the repo, or the task is so broken that every path is a guess.

Long command output goes under `.atelier/tasks/<id>/`. Read the tail.
