# Quick Look GLB load-time experiments

**Full protocol:** [`PROTOCOL.md`](./PROTOCOL.md) — Dex epic orchestration, sequential subagents, external research, size-ordered benches, acceptance gates.

## Primary metric

`total_load_ms = EntityLoader.load + StillRenderer.capture` (256² first still).  
Aggregate: **sum of per-asset median `total_load_ms`**.

## Frozen corpus

**v2** (current): `corpus.json` — 10 files in `/tmp/glb-preview-load-bench/set/` (~754 MB).  
**v1** archived as `corpus-v1.json`. Do not change mid-campaign.

## How to bench

```bash
LABEL=<id> ./scripts/load-bench.sh
```

Assets run **smallest → largest**. Early abort only for crashes/severe regressions — **never** KEEP without the full corpus. Prefer same-machine champion control.

## Dex

Epic: **Optimization Experiments** (one L1 task per `EXP-NNN`).  
Start child before edits; `dex complete` with KEEP/REJECT/INCONCLUSIVE evidence. Search `WHAT-WE-TRIED.md` before creating a new EXP task.

## Champion

See `results.json` / `WHAT-WE-TRIED.md` (corpus-v2 `baseline-v2`).
