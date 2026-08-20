# Thin Orchestrator + Specialist Subagents for GLB Load Experiments

**Date:** 2026-08-20  
**Status:** Approved (brainstorm)  
**Applies to:** `experiments/PROTOCOL.md`, Dex epic `Optimization Experiments`

## Problem

A single long-lived orchestrator that researches, invents experiments, implements, and benches accumulates noisy context and stops being creative. Parallel benches also corrupt timing. We need a thin campaign loop with specialist agents and Dex as the durable handoff.

## Goals

- Keep orchestrator context small: dispatch, gate, promote KEEP, cleanup.
- Let a researcher be creative in a fresh context (docs, GitHub, profile, `WHAT-WE-TRIED`).
- Let an executor run exactly one experiment end-to-end without merging to champion.
- Preserve statistical discipline: no parallel benches; full corpus for KEEP; pre-run delete for bad proposals only.

## Non-goals

- Changing the frozen corpus or primary metric.
- Auto-merging KEEP without an orchestrator promotion step.
- Deleting completed REJECT tasks from Dex (ledger history must survive).

## Architecture (Approach 1 — Thin dispatcher)

```text
Orchestrator
  → Researcher (≤3 dex EXP tasks)
  → Pre-run gate (delete rejects)
  → Executor (serial; one EXP)
  → On KEEP: Orchestrator/Integrator promotes to champion
  → On REJECT: Executor discards worktree
  → Researcher may run ahead while a bench is in flight
```

### Roles

| Role | Creates dex EXP? | Edits code? | Benches? | Merges champion? |
|------|------------------|-------------|----------|------------------|
| Orchestrator | No (may delete pre-run) | Promote only | No | Yes (KEEP) |
| Researcher | Yes (≤3 ranked) | No | No | No |
| Executor | Completes only | Yes (worktree) | Yes (serial) | No |
| Integrator (optional) | No | Merge only | No | Yes (delegated) |

### Decisions locked in brainstorm

- Researcher **creates** Dex EXP tasks; orchestrator **deletes** if rejected pre-run; else dispatches executor.
- Pre-run delete only. Post-bench always `dex complete` with KEEP | REJECT | INCONCLUSIVE.
- Up to **3** ranked EXP tasks per research spawn.
- Research **may** run in parallel with an in-flight executor (read-only + `dex create`); benches remain serial.
- KEEP promotion is **orchestrator** (or optional Integrator), not the executor.
- REJECT cleanup (worktree/branch) is **executor**; orchestrator verifies orphans periodically.

## Handoff packets

### Researcher packet

- Epic id (`Optimization Experiments`)
- Current champion label + `sum_median_total_ms`
- Full `WHAT-WE-TRIED.md` + recent `results.json` experiments
- Forbidden list + `experiments/PROTOCOL.md`
- Optional profile summary
- Instruction: create ≤3 ranked NEW/VARIANT tasks only

### Dex EXP task (researcher-authored)

- Hypothesis, classification (NEW/VARIANT), `parent_champion`
- Approach (one change), likely files, research citations
- Done-when, rank 1–3

### Executor packet

- Dex task id + `EXP-NNN` label
- Worktree/branch from current champion SHA
- Bench command, corpus path, noise rule
- Do not merge; on KEEP return SHA + report

### Return packet

- Decision, metrics, SHA/path (if KEEP), complexity, ledger paths updated

## Gates

1. **Pre-run:** duplicate / weak / out-of-scope / false-optimization → `dex delete`.
2. **Dispatch:** one executor; `parent_champion` must match current champion or task is deleted / re-parented.
3. **Post-run:** executor completes Dex + updates `WHAT-WE-TRIED` / experiment row in `results.json`; orchestrator updates champion pointer only on successful promote.

## Ledger ownership

| Artifact | Owner |
|----------|--------|
| Dex EXP create | Researcher |
| Dex EXP delete (pre-run) | Orchestrator |
| Dex EXP complete | Executor |
| `WHAT-WE-TRIED.md` + experiment rows | Executor |
| `results.json` champion pointer | Orchestrator on KEEP promote |
| `baseline.json` / `corpus.json` | Immutable unless user changes corpus |

## Stale queue

Queued EXPs created while a KEEP is in flight may name an outdated `parent_champion`. Before dispatch, orchestrator re-checks; if mismatched, delete or `dex edit` parent and re-queue (or re-research).

## Implementation follow-up (out of scope for this spec’s approval gate)

1. Update `experiments/PROTOCOL.md` (and short `README.md` pointer) to encode this agent model.
2. Align existing Dex epic children with the new gate/promote rules.
3. Optional: prompt templates for Researcher / Executor / Integrator packets.

## Success criteria

- Orchestrator can run a round without reading full bench logs.
- Researcher can invent and `dex create` ≤3 tasks from a clean context.
- Executor never merges to champion; KEEP only lands via orchestrator promote.
- No two benches overlap; research-ahead does not start a second bench.
