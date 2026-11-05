# Glossary

The words next-workflow uses, with these meanings. `wait-what` re-pitches in these words.

## Board

| Word | Meaning |
| --- | --- |
| **board** | The Atelier backlog (`.atelier/backlog.jsonl`, CLI and MCP `backlog`). The plan *and* the history of what happened. |
| **epic** (L0) | A goal made of tasks, usually from one spec. |
| **task** (L1) | One unit of working, testable behaviour, end to end. Has acceptance tests, Done when, and the files it owns. |
| **subtask** (L2) | A part of a task, 0–6 per task. Only for a separate owner, a fixed order, or parallel work. |
| **one-off** | A task with no epic: a bug fix, a spike, or a record of off-plan work. |
| **start / complete** | Start when someone works on it; complete when its code is accepted, with proof. |
| **ruling** | A decision made instead of stalling: `Ruling: what — why — cost if wrong`, written on the task. |

## Define

| Word | Meaning |
| --- | --- |
| **ask** | What the user said they want, in their words. |
| **design tree** | Every open decision, each branching into the decisions that hang off it. |
| **frontier** | The decisions whose prerequisites are settled: the ones you can ask about now. |
| **spec** | The authority for *what* and *why*: goals, non-goals, decisions, acceptance examples, a picture of how it works. Written as the L0 epic's description (a single task's, when small). Conflicts resolve against it. |
| **plan** | An existing document that says *how*. `n-breakdown` puts it on an L0 epic as it is and breaks it into tasks. |
| **acceptance example** | Given / when / then in the spec. Becomes at least one acceptance test. |

## Build

| Word | Meaning |
| --- | --- |
| **acceptance test** | A named test, written on the task before code, that fails today and passes when the task is done. |
| **red** | The test runs and fails for the expected reason (behaviour missing, not a typo). |
| **green** | The test passes and the whole suite is still green, output clean. |
| **refactor** | Clean-up while green. No new behaviour. |
| **tracer bullet** | The first task of an epic: the thinnest working path through every layer, proven before anything fans out. |
| **seam** | The place a behaviour is tested from. As few and as high as possible, named in the spec. |
| **proof** | Fresh evidence from this turn: command + result, or a capture of the real app. |
| **before / after** | Captures of the surface a task changes: at start and at land, same framing, in `.atelier/tasks/<id>/captures/`. |
| **artifacts** | Everything agents make: `.atelier/tasks/<id>/` per task, `.atelier/research/` for notes. Tracked in git. |
| **brief** | What an agent receives: one task, its spec excerpt, its files. No session history. |
| **worktree** | `.worktrees/<task-id>` inside the repo, used when an agent builds the task. The main checkout stays on `main`. `n-execute` stays in the checkout it was given. |
| **land** | Rebase the worktree on `main`, fast-forward `main`, remove the worktree. No PRs. |
