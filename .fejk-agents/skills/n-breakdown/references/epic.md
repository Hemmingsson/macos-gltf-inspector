# Epics with many tasks

For 20–50 tasks from one spec.

- **Waves.** Group tasks into waves: wave 1 is the tracer bullet alone; later waves fan out. Prefix the task name with its wave (`W2 · …`) so `backlog list` reads as a schedule.
- **Prefactor first.** Make the change easy, then make the easy change: a behaviour-preserving task before the tasks that need it.
- **Expand–contract** for wide refactors: add the new form, migrate callers in batches, delete the old form — three kinds of task.
- **Shared interfaces first.** Tasks that change a shared interface go in an early wave and block the tasks that use it.
- **Parallel work.** Within a wave, tasks with disjoint `Owns:` lists can run in parallel. Two tasks owning the same file are sequential — wire `--blocked-by`.
- **The epic** holds: spec link, wave table, the global constraints copied verbatim from the spec (exact values reviewers check).
- **Coverage table** on the epic: acceptance example → task id. An unmapped example is a gap; a task with no example is scope creep or a missing spec row.
- **Add, don't pad.** When build reveals a missing task, add it and a ruling on the epic; leave the spec alone unless a decision changed (then the spec changes first).
