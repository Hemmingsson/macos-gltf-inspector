---
name: n-subagents
description: Build ready tasks by dispatching one n-implementer per task, then a task review. Use when more than one task is ready, or one task is large, and the harness can dispatch agents.
---

# n-subagents

You conduct. Implementers write code. Reviewers judge it. In this mode you write no product code.

Do not ask whether to continue between tasks. Write `Ruling: what — why — cost if wrong` on the task and keep going. Stop only when the next step is irreversible or destructive, deletes data or leaves the repo, or the spec is so broken that every path is a guess.

After compaction, trust the board and `git log` over memory. A task already complete is not dispatched again.

## Per task

1. **Start.** `backlog start <id>`. Make the worktree (`n-worktrees`) and record `BASE` before the dispatch. Something visible changes: send `n-visualizer` (background) for the `before` capture.
2. **Dispatch** `n-implementer` with the brief in [dispatch.md](references/dispatch.md). Record the agent id. Model: the table in that file.
3. **Report.** `DONE` → step 4. `NEEDS_CONTEXT`: answer it and resume the same agent. `BLOCKED`: split the task, or re-dispatch one model tier up. Read the report file. The status line is not the evidence (`n-verify`).
4. **Review.** From the worktree, write `.atelier/tasks/<id>/review.diff` (`git -C .worktrees/<id> log --oneline BASE..HEAD`, `--stat`, `diff -U10`). Dispatch `n-task-reviewer` with the task, the report path, and the diff path (`n-review`). Spec and quality are both required. Never a brief that says "don't flag X".
5. **Fix.** Critical, Important, or a failed spec verdict: resume the same implementer with the findings verbatim, then re-review only the fix. Round 4: a fresh implementer, one tier up. After round 4, a ruling on the task for each open finding, then move on. Minor findings go on the task.
6. **Land.** Review clean, or every open finding has a ruling: `n-full-send`.

Independent tasks go out together (`n-parallel`). A task that shares a file waits until the earlier worktree has landed on `main`.

While agents run, update the board and the next brief. Do not poll.

## After the last task of an epic

Dispatch `n-code-reviewer` over `<first BASE>..main` with the spec (`n-review`). One fix wave, then complete the epic with a short result.

Briefs and the report shape: [dispatch.md](references/dispatch.md).
