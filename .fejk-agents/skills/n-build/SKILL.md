---
name: n-build
description: Choose how ready tasks get built. Use when tasks are on the board and the work is to implement them.
---

# n-build

Pick the skill. Keep the board true. You do not write product code when agents are building.

| Ready work | Skill |
| --- | --- |
| User said no subagents, or the harness cannot dispatch | `n-execute` |
| One small task, this session | `n-execute` |
| Several tasks, or one large, and you can dispatch | `n-subagents` |

Independent failures during a task: `n-parallel`. A claim that something passes: `n-verify`. Landing: `n-full-send`.

## Board

- Start a task when work begins. Complete it only from `n-full-send`, after the user approves.
- Every capture, diagram, round, ruling, and result goes on the task as it happens, picture first (`n-backlog`).
- A finding that is new work becomes a new task under the epic.
- Off-plan work still gets a task, completed at once, so the history is whole.

**Done when** every picked task is complete on `main` with proof, or has a ruling on why not. An epic's final review is clean before the epic itself is completed.
