---
name: n-review
description: Dispatch n-task-reviewer or n-code-reviewer on a diff and act on the findings. Use after a task or feature is green, before landing, or when those findings arrive.
---

# n-review

Dispatch a reviewer. Do not review the diff yourself in its place. The reviewer gets files, not your session history.

## Request

1. Write the review file from the checkout that holds the change (`git -C .worktrees/<id>` when the task has a worktree): `log --oneline BASE..HEAD`, `diff --stat`, and `diff -U10`, into `.atelier/tasks/<id>/review.diff`. `BASE` is the commit recorded when the task started, never `HEAD~1`.
2. Dispatch `n-task-reviewer` for one task, or `n-code-reviewer` for the whole epic, with the task or spec, the diff path, and the proof already run.

When you cannot dispatch, say `Review: self` on the task and apply the receive rules below yourself. A self-review is weaker. Say that in the report.

## Receive

Findings are **Critical / Important / Minor**, each with file:line.

| Severity | Action |
| --- | --- |
| Critical, Important | Fix now, re-run the covering tests (`n-verify`), scoped re-review |
| Minor | Note on the task. The final review decides |

Check each finding against the code before acting. A wrong finding gets a reply with evidence (the test, the line, the spec row). An unclear finding: ask before implementing it.

**Done when** no Critical or Important finding is open without a fix or a written ruling.

Sol review is `n-sol-loop`, not this skill.
