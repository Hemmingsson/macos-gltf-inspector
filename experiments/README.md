# Quick Look GLB load-time experiments

Orchestrator-only campaign. Subagents implement and bench in isolation.
The champion is this working tree minus rejected experiment flags.

## Primary metric

User-visible path: select GLB → `EntityLoader.load` (QL convert) → first still frame
(`StillRenderer` capture, the in-process stand-in for first usable pixels).

`total_load_ms = load_ms + first_render_ms`

Stages we cannot isolate (GPU upload vs shader vs decode) are recorded as `null`.

## Frozen corpus

Exactly 10 files in `/tmp/glb-preview-load-bench/set/`.
Metadata: `corpus.json`. Do not change the set.

## How to bench

```bash
LABEL=<id> ./scripts/load-bench.sh
```

Writes `/tmp/glb-preview-load-bench/<stamp>-<label>.json`.
Copy accepted runs into `experiments/results/`.

## Champion

Current: `baseline` (see `baseline.json`).
Accepted experiments become the new parent. Rejected experiments never land on champion.

## Rules

- Search `WHAT-WE-TRIED.md` before proposing anything.
- One hypothesis per experiment.
- Accept only if: real drop beyond noise, no correctness skip, no extra complexity.
- Skipping required work (prepare, animations, textures, document for host) is measurement-only, never a keep.
