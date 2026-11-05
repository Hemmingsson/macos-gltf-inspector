---
name: n-breakdown
description: Break a spec, an existing plan, or a clear ask into an epic, tasks and subtasks on the board. Use when work needs tasks before building, or the user asks to break down a plan.
---

# n-breakdown

Turn the source into tasks someone can pick up cold, on the board (`n-backlog`). The source stays the authority: an existing plan is broken down as it is, never rewritten.

1. **Read the source** — an approved epic (the spec), a written plan, or an ask — and the code it touches. A written plan with no epic: create the L0 epic with the plan as its description (link the file, keep the words), add a picture of how it will work, and treat the plan as the authority.
2. **Pick the shape** and say it in one line:

   | Work | Shape |
   | --- | --- |
   | One change | one task |
   | A feature | one task with 1–6 subtasks |
   | A project | epic (L0) → tasks (L1) → 0–6 subtasks (L2) each |

3. **Cut tasks by behaviour.** Each task delivers working, testable behaviour end to end, through every layer it needs. Task 1 of an epic is the **tracer bullet**. Unknowns go early. A subtask exists only for a separate owner, a fixed order, or parallel work.
4. **Write each task** from [task.md](references/task.md). Every task description carries this heading, filled:

   ```markdown
   ## Acceptance tests — write each red before any code
   - `<TestName>` — given …, when …, then …
   ```

   plus the files it owns and the epic it argues from. A task that changes something visible gets a picture: send `n-visualizer` (background) for each and keep breaking down. A subtask gets its scope in one line and its own red-first check.
5. **Wire real dependencies** with `--blocked-by`, after `backlog show` confirms the blocker is still open. Tasks whose owned files don't overlap can run in parallel (`n-parallel`). Tasks that share a file are ordered: the later one is `--blocked-by` the earlier, and it starts only after that worktree has landed.
6. **Check** `backlog list --ready` shows a sensible next set.

**Done when** every acceptance example in the source maps to an acceptance test on some task, and every task has a check that can fail. Report: shape, epic id, ready ids, any example left unmapped.

Epics of 20+ tasks: [epic.md](references/epic.md). Board commands and formats: `n-backlog`.
