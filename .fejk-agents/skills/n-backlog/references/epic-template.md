# Epic (L0) = spec

The epic's description is the spec: the authority for *what* and *why*. Tasks argue from it, and conflicts resolve against it. A small change uses the same sections, a line or two each, on a single task. Link to what `AGENTS.md` or research notes already say; don't copy it.

````markdown
```webview aspect=16/9
How it will work | .atelier/tasks/<epic-id>/diagrams/<slug>.html
```

**Status:** draft | approved YYYY-MM-DD

## Why
The problem, who has it, and what success looks like to them.

## Goals / non-goals
- Goal: …
- Non-goal: … (explicitly not doing)
- Anti-goal: … (would make it a failure even if it works)

## Decisions
| Decision | Choice | Why | Whose |
| --- | --- | --- | --- |
| … | … | … | user / my call |

## Approaches considered
Two or three, each with its trade-off; which was picked and why.

## Behaviour — acceptance examples
One row per observable behaviour. Each row becomes at least one red test.

| # | Given | When | Then |
| --- | --- | --- | --- |
| A1 | … | … | … |

## Test seams
Where the examples are tested: as few seams as possible, as high as possible, existing ones first. For each seam, what it catches and what it misses.

## Constraints
Exact values, formats, limits. Reviewers check these word for word.

## Left to the builder
What breakdown and the implementer may decide.

## Waves and coverage
Filled by `n-breakdown`: the wave table, and acceptance example → task id.
````

The picture leads, above every heading. For UI, put a `create-wireframe` webview of the target there too, plus `![now](…/captures/now.png)` of today's surface. Once a live demo exists, it replaces the diagram at the top.
