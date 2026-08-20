# GLB load performance — campaign closeout

Stopped 2026-08-20 under PROTOCOL: `reject_only_batches ≥ 3` with empty `accepted_queue`. Residual refresh confirms the same wall: **09+10 ≈ 72%** of sum, nested **`texture_ms`** inside decode/scene. No new phase cell cleared the ~224 ms noise floor.

## Headline

| | ms | vs baseline-v2 |
|--|---:|---:|
| **baseline-v2** (immutable) | **16387.4** | — |
| **Champion cp-003** (`173fc71`) | **7464.8** | **−54.4%** (−8923 ms) |
| Best tip (cp-002, pre–029) | 7372.9 | −55.0% |

Primary metric: sum of per-asset median `EntityLoader.load + StillRenderer.capture` on frozen corpus-v2 (10 GLBs, 5 reps).

## What moved the needle

| KEEP | Candidate Δ | Integrated tip effect | Idea |
|------|------------:|----------------------:|------|
| EXP-009 | −47% | dominant in cp-001 | cutout-as-mask for factor-1 BLEND (opacity tax on 07) |
| EXP-006-v2 | −6.8% | cp-001 | packed SIMD mesh path |
| EXP-011 | −4.4% | cp-001 | material cache by `ObjectIdentifier` |
| EXP-017 | cand −554 → tip −247 | cp-002 | packed float3 LowLevelMesh |
| EXP-029 | cand −243 → tip +92 | cp-003 | cap skeletal densify ≤30 fps |

Checkpoints: cp-001 → 7620; cp-002 → 7373; cp-003 → 7465 (candidate→tip shrink on 017/029).

## Residual wall (cp-003)

| Asset | Share | Dominant phase |
|-------|------:|----------------|
| 10-bot_mecha_warrior | 42.9% | texture (~2937 ms nested) |
| 09-realistic_animals | 29.5% | texture (~1833 ms) |
| 08-cinema_projector | 10.5% | one 8K PNG `TextureResource.generate` |

Aggregate phase sums (overlay): texture ~5852 · decode ~6846 · scene_build ~7442 (nested). I/O + parse are thin (~88 + ~138 ms).

## Exhaustion

Post–cp-003 reject-only streak (030 ImageIO no-copy, 031 MR swizzle/16bpp pack, 032 CGImage eviction) plus earlier texture folklore (CreateOptions / mip / compression / Metal upload / prefetch / UV fuse) — all banned or Must-not-retry. Lane B/C-scene research returned **none** (leftovers under noise without texture-path wins).

Practical ceiling: RealityKit `TextureResource.generate` on large rasters for 09/10. Further wins need new measured phase evidence (e.g. GPU upload split), not unprofiled CreateOptions variants.

## Ledger

- Protocol / workers: `.cursor/skills/glb-load-experiments`, `.cursor/agents/glb-load-*`
- Numbers: `experiments/results.json`, `residual-map.json`, `WHAT-WE-TRIED.md`, `baseline.json`
- Bench: `LABEL=<id> ./scripts/load-bench.sh`
