# Task review (one task, one diff)

Used by `n-task-reviewer`.

One task, one diff, two verdicts. Read-only: the working tree, index and HEAD stay as they are.

## Read

The task (`backlog show <id>`), the spec constraints in the brief, the implementer's report, and the diff file. Read the diff file once; its context lines are the changed code. Look outside it only to check a risk you can name (a changed contract → its call sites), and name the risk.

The report is claims. Verify each against the diff; a stated rationale ("kept simple per YAGNI") never lowers a finding's severity. The implementer's test run is the test evidence — run a focused test only for a specific doubt.

## Verdict 1 — spec

- **Missing**: an acceptance test or Done-when item not implemented, or claimed without code.
- **Extra**: behaviour the task did not ask for.
- **Misread**: the right feature built the wrong way.
- **Red skipped**: no red evidence for an acceptance test.

A requirement you cannot judge from the diff: mark ⚠️ and say why.

## Verdict 2 — quality

Tests assert real behaviour, not mocks · edge cases from the spec covered · errors handled · each file one job · no duplicated logic block · test output clean.

## Reply

Begin with the verdicts. Every line is a verdict, a finding, or a check you ran.

```text
Spec: ✅ | ❌    Quality: ✅ | ❌
Critical | Important | Minor — path:line — what breaks, when — direction
⚠️ — what can't be verified from the diff
```

**Important** = the task can't be trusted until fixed. Not everything is Critical.
