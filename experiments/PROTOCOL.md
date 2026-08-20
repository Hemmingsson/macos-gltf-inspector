# PROTOCOL

Ledger: `experiments/{results.json,WHAT-WE-TRIED.md,residual-map.json}`. Match existing JSON keys.

| | |
|--|--|
| Metric | Sum of per-asset median `EntityLoader.load + StillRenderer.capture` |
| Noise | `\|delta\| < 3%` of `recorded_control` unless ≥8/10 same direction |
| Baseline | `baseline.json` (`baseline-v2`) immutable |
| Champion | Tip after last checkpoint |
| Residual | `residual-map.json` — gate research; refresh after checkpoint / when `sha` ≠ control |
| Bench | `LABEL=<id> ./scripts/load-bench.sh` — Benchmarker only; never parallel |
| Dex | Epic `7uyt0wel`; no dex IDs in commits |
| REJECT always | Quality cuts; skip required work; corpus special-case; prepare-skip; v1-as-v2 |

Tiny+ugly → REJECT. Delete-code wins → KEEP.  
OK: researchers ∥ implementers ∥ one benchmarker. Forbidden: 2 benches; implementer benches; merge in Experiment; 2 agents / worktree.

`recorded_control`: reuse while `sha == BATCH_CHAMPION_SHA`; rewrite after checkpoint. Invalidate queued EXPs when sha changes.

## Residual gate

Researchers may `dex create` only with target asset(s) that can clear the noise floor (or delete-work + named-asset concentration). Prefer `(asset, phase)` when phases exist. Lane budget follows residual % (today: C=09/10).

Hard bans until a residual cell proves otherwise: unprofiled CreateOptions; fused UV (012/024); concurrent prefetch (018); mapped `GLTFAsset(data:)` (020). VARIANT of REJECT needs new measured evidence.

## Experiment

1. `cold-start.sh`. `BATCH_CHAMPION_SHA` = tip / control sha.
2. Abandon if Stop; else checkpoint if due and queue nonempty.
3. ≤3 researchers (residual excerpt required) → gate → ≤3 implementers on champion sha.
4. Benchmarker `mode=candidates`. During bench: research only if residual sha still matches.
5. KEEP → `accepted_queue` (≤1/batch). `NEAR_MISS` → Tweak. REJECT → discard. No integrate.
6. Reject-only batch → `reject_only_batches++`. Reset on KEEP or checkpoint. `AUTONOMOUS=1`: never ask. Goto 2.

Lanes: A I/O·prepare · B parse·decode · C textures·materials·scene·still.  
KEEP: beyond noise · correct · simple · honest.  
`NEAR_MISS`: under-noise same-direction (≥5/10 or concentrated on residual targets). Not Must-not-retry yet.

## Tweak (≤2)

Same worktree, narrower same-family change. Implementer never benches. Benchmarker may subset via temp `GLB_LOAD_BENCH_MANIFEST` (residual assets only); full 10 for KEEP/checkpoint. Clear regress / inverted targets → final REJECT + Must-not-retry.

## Checkpoint (queue nonempty)

When: queue ≥2 (≥3 autonomous) · ≥3 reject-only batches since accept + queue≥1 · hot-file conflict · user/time box.

1. Integrator merges ordered queue.
2. Benchmarker `mode=checkpoint` → tip metrics + control; note `candidate_vs_tip_shrink`.
3. Orchestrator: `checkpoints[]`, clear queue, `reject_only_batches=0`, WHAT-WE-TRIED champion, `update-residual-map.sh`, fix dex parents.

## Bench

Small→large; full 10 for KEEP/checkpoint. Abort on fail / ~+15% on ≥2 of first 4. Logs: `/tmp/glb-preview-load-bench/agent-logs/` + `summarize-bench-log.sh`. Diagnosis on every non-KEEP. KEEP branches until checkpoint; merges `perf:`.

## Stop

`reject_only_batches ≥ 3` + empty queue → no research; refresh residual (rebench tip if needed); if still 09/10-bound with no new phase cell → `PERFORMANCE-OPTIMIZATION.md` + complete epic. Also: several checkpoints with no baseline gain · complexity/platform wall · target.

## Packets

Do not paste PROTOCOL into Task prompts. Parent sends fields listed in each agent file.
