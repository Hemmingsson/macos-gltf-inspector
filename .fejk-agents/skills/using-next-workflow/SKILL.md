---
name: using-next-workflow
description: Injected at session start. Routes work into next-workflow at the stage its artifacts have reached, and keeps the board true.
disable-model-invocation: true
---

<SUBAGENT-STOP>
Dispatched as a subagent for one task? Skip this; follow your brief.
</SUBAGENT-STOP>

# next-workflow

Spec-driven and test-first. Words mean what `GLOSSARY.md` (plugin root) says.

```text
brainstorm → breakdown → build (red → green → refactor) → review → land
```

## Enter where the work is

Look at what exists, then invoke the first skill that is missing. Say the entry in one line.

| What exists | Next |
| --- | --- |
| A fully specified small change, or a bug | a task on the board (`n-backlog`), then `n-tdd` |
| An idea with open decisions | `n-brainstorm` |
| A spec, or a written plan | `n-breakdown` (keep the plan; break it down) |
| Tasks on the board | `n-build` (then `n-execute` or `n-subagents`) |
| Independent tasks or failures | `n-parallel` |
| A diff to judge | `n-review`. "sol loop" → `n-sol-loop` |
| About to say it passes, is fixed, or is done | `n-verify` |
| A task is reviewed and ready to land, or the user said "full send" | `n-full-send` |

## The board is the truth

The Atelier backlog is the plan and the history: commands, rich formats and artifact paths in `n-backlog`. Everything agents make lives in `.atelier/` (tracked in git), per task in `.atelier/tasks/<id>/`. Keep the board as close to reality as you can:

- **No code change without a task in progress.** `backlog start` an open task, or create a one-off (bug fix, spike) and start it — before the first edit.
- **Start** a task the moment someone works on it. **Complete** it when its code is accepted, with proof in the result.
- Work that happened off-plan still gets a task — under its epic or standalone — completed at once, so the history is whole.
- After compaction, the board and `git log` are what happened. Trust them over memory.

## Three laws

1. **Spec before code** for anything with an open decision.
2. **Red before green.** No production code without a failing test you watched fail.
3. **Proof before done.** `n-verify`: fresh evidence on the task, not a belief — with a picture first: before/after captures for what you can see, a diagram for what you can't.

Keep going between stages and tasks. Stop only for: a decision that is the user's, an irreversible or outward-facing action, or a spec so broken every path is a guess. Everything else is a **ruling** written on the task.
