---
name: n-parallel
description: Dispatch independent tasks or independent failures together. Use when two or more pieces of work share no files and no outcome.
---

# n-parallel

One agent per independent piece of work. Send every dispatch in the same message. Separate messages run one after another.

Each brief names one domain, the task id or the failing test names, the files it may touch, the files it must leave alone, and the report to write. No session history.

## Tasks

Compare `Owns:` lists.

- No shared files: one `n-implementer` each, each in `.worktrees/<id>` (`n-worktrees`), in one message.
- A shared file: the later task starts only after the earlier worktree has landed on `main`.
- Land worktrees one at a time.

## Failures

Group by test file or subsystem.

- Different causes, no shared files: one agent each, in one message. Paste the failing test names into each brief.
- One fix might clear the others, or you do not yet know the split: one agent investigates. Dispatch only after the groups are real.
- Do not parallelize a shared file, a shared resource, or a bug you have not located.

## After they return

Read each report. Confirm the diffs do not touch the same files. Run the project's whole suite (`n-verify`). You integrate. The workers do not dispatch agents of their own.
