# Briefs

A brief describes one task. It never carries session history or earlier tasks' summaries. Hand big artifacts over as file paths.

## Implementer brief

```text
Task: <id> — read `backlog show <id>` first; it is your requirements.
Spec: epic <epic-id>, examples <A…>   Global constraints: <verbatim from spec / epic root>
Worktree: .worktrees/<id>   Owns: <files>   Others' files: leave as they are.
Interfaces from earlier tasks: <signatures it can't know>
Rulings that bind this task: <ruling lines, if any>
Report: write the full report to .atelier/tasks/<id>/report.md; reply with the short status.
```

## Implementer report

Write the full report to the path in the brief:

- What changed (files) and why
- **TDD evidence** per acceptance test: red command + failing line; green command + pass count
- Suite result, with any red named — yours or not
- Concerns, rulings you needed, things the user should know ("removed X in favour of Y")
- Draft `backlog complete --result` text that opens with the picture: `![after](.atelier/tasks/<id>/captures/…)` for a visible change, a diagram (`create-diagram`) for a structural one. Do not run `backlog complete`. The conductor does that in `n-full-send`.

Reply with only:

```text
Status: DONE | DONE_WITH_CONCERNS | NEEDS_CONTEXT | BLOCKED
Commits: <sha subject>…
Tests: <one line, e.g. 14/14, output clean>
Concerns: <or none>
Report: <path>
```

After review findings you are resumed: fix, re-run the covering tests, append a fix section to the same report, reply with the same five lines.

## Task-reviewer brief

```text
Task: <id> (requirements)   Spec constraints: <verbatim>
Report: .atelier/tasks/<id>/report.md (claims, not evidence)
Diff: .atelier/tasks/<id>/review.diff   (git -C .worktrees/<id> log --oneline BASE..HEAD; diff --stat; diff -U10)
```

Let the reviewer raise every finding. A brief that says "don't flag X" pre-judges the review.

## Code-reviewer brief (final)

```text
Epic (spec): <id>   Range: <first BASE>..main
Deferred minors and rulings: backlog show <epic>
```

## Spec-reviewer brief

```text
Epic (spec): <epic-id>   Domain: <e.g. macOS Metal app engineer>
```

## Background work

`n-visualizer` always runs in the background. So can any agent whose result you do not need for the next step.

| Harness | How |
| --- | --- |
| Claude Code | Agent tool with background on; you are notified when it ends |
| Cursor | the agent's `is_background: true`, or ask for it in the call |
| Codex | `spawn_agent`, keep working, `wait_agent` only when you need the result |

## Which model

Use the cheapest seat that can do the job. Name the model in the dispatch. An omitted model inherits the session and silently picks the most expensive seat.

| Job | Seat |
| --- | --- |
| Yes/no, pick one, score | **Jev** via atelier-lm (`lm_jev_noul`, `lm_jev_choice`, `lm_jev_score`; CLI `atelier-lm jev …`) |
| Commit message, task name, one-paragraph summary, one-file mechanical diff | **Qwen** via atelier-lm (`lm_qwen_complete`, `lm_qwen_review`; CLI `atelier-lm qwen …`) |
| Brief already contains the code, tests, or build steps | fast worker (`fast-delegation`) |
| Judgment across files; reviews | standard model (`fast-delegation`) |
| Stuck after round 3, the epic review, or architecture | strongest model (`fast-delegation`) |

`atelier-lm status` shows what is up. When a seat is down, move one row down. Do not skip the step.
