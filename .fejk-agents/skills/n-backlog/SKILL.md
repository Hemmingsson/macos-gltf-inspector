---
name: n-backlog
description: Atelier backlog commands, rich task formats, and where agent artifacts go. Use when creating, starting, editing or completing an epic, task or subtask, or when saving a capture, diagram, report or research note.
---

# n-backlog

The board is `.atelier/backlog.jsonl` in the main checkout, tracked in git. Drive it with the `backlog` CLI, or the `backlog` MCP server (`create_task`, `update_task`, `list_tasks`) where the CLI can't run.

```bash
backlog create "Name" --description "…" [--parent <id>] [--blocked-by <id>,<id>]
backlog list --ready | --in-progress | --all        backlog show <id> --full
backlog start <id>                                  backlog edit <id> --description "…"
backlog complete <id> --result "…" --commit <sha>   # or --no-commit
```

`edit --description` replaces the whole body: start from `backlog show <id> --full`. Other flags: `backlog <cmd> --help`.

## Levels

| Level | Holds |
| --- | --- |
| **L0 epic** | The spec *is* the epic: why, goals, decisions, acceptance examples, seams, constraints, plus a diagram of how it will work ([epic template](references/epic-template.md)) |
| **L1 task** | Acceptance tests (red first), files owned, Done when, and a before capture for anything visible |
| **L2 subtask** | Scope in one line and its own check |

## Pictures on top

The user reads pictures faster than prose (dyslexia), and the board shows the result first, then the description. So:

- **Description:** the most visual thing goes at the very top, above any heading: a live demo of the feature, else a diagram (`create-diagram`) or wireframe (`create-wireframe`), else the before capture. Prose comes after.
- **Result:** opens with its proof: the live demo or `![after](…)` (next to `![before](…)`), or the diagram of what changed. Then the test evidence, then what changed in words.
- Every L0 gets a picture of how it will work. Every visible task gets a before and an after capture.
- Embed with a `webview` fence (diagram, wireframe, live HTML/Svelte preview) or an image. How to make and embed each kind: [formats.md](references/formats.md).
- A picture takes minutes. Hand it to the `n-visualizer` agent **in the background** (task id, the question it answers, the kind) and keep writing or building; it puts the picture on top of the task itself. Before you edit that task's description, re-read it so you keep its block.

## Keep the task current

Each artifact goes onto its task the moment it exists, not at the end. Edit the description (`backlog show <id> --full`, then `backlog edit`) when you make a capture, a diagram or a demo, when a ruling is made, and when scope changes. Anyone opening the task mid-work sees where it stands.

## Where agent artifacts go

| What | Path |
| --- | --- |
| Anything for one task (captures, proof, diagrams, report, review diff, scratch) | `.atelier/tasks/<task-id>/` — make whatever subfolders help |
| Research notes | `.atelier/research/YYYY-MM-DD-<slug>.md` |
| Captures with no task yet | `.atelier/artifacts/` |
| Session handoff | `.agents/tmp/handoff/<YYYY-MM-DD-HHMM>-<project>.md` (not tracked) |

`.atelier/` is tracked in git: commit board and artifact changes with the work they belong to.
