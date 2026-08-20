# What we tried

Do not retry the **Must not retry** column. Residual pie/phases: `residual-map.json` (authoritative). Noise: `results.json` `noise_rule`.

## Champion

| Label | ms | Notes |
|-------|---:|-------|
| **cp-003** | **7464.8** | Tip `173fc71` (EXP-029); −54.4% vs baseline-v2; tip +91.9 vs cp-002 |
| cp-002 | 7372.9 | Tip `1aceeda`; −55% vs baseline-v2 |
| cp-001 | 7620.2 | 006-v2+009+011 |
| baseline-v2 | 16387.4 | Immutable |

## Residual (cp-003)

09+10 ≈ **70%** of sum. Convert-bound: nested `texture_ms` dominates `decode`/`scene_build` (see `results/cp-002-phases.json`). Research must name assets that can clear ~3% noise (~221 ms).

## Tried

| ID | Result | Must not retry |
|----|--------|----------------|
| EXP-000 | cleanup sleep | Artificial delay |
| EXP-001 | informal v1 baseline | Treat as official |
| EXP-002 | skip anims −20% | Disable clips to win |
| EXP-003 | skip document −2.4% | Skip outliner for noise |
| EXP-004 | skip prepare −14.5% | Ship prepare skip (cheaper prepare VARIANT OK) |
| EXP-005 | REJECT prepare never ran | Prepare win when prepare doesn’t run |
| EXP-005-v2 | REJECT dirty control | Same without prepare-only / clean control |
| EXP-006 | tentative v1 KEEP | Merge on frozen delta alone |
| EXP-006-v2 | **KEEP** −6.8% | — |
| EXP-007 | REJECT warm bias | Corpus win when non-targets move equally |
| EXP-008 | REJECT −0.12% | ARGB sibling-cache w/o new evidence |
| EXP-009 | **KEEP** −47% (07 −89%) | OpacityTexture back on cutout w/o fidelity gate |
| EXP-010 | REJECT +2.2% | LowLevel swizzle w/o 09/10 evidence |
| EXP-011 | **KEEP** −4.4% | Blind material cache w/o ObjectIdentifier evidence |
| EXP-012 | REJECT +2.0% | Fused UV wrap+flip w/o UV-dominant residual |
| EXP-013 | REJECT +0.57% | BIN passthrough w/o prepare-concentrated 09 win |
| EXP-014 | REJECT −2.93% under noise | Direct-float pack w/o ≥8/10 or beyond-noise |
| EXP-015 | REJECT +5.9% | Full-RGBA Metal upload w/o 09/10 evidence |
| EXP-016 | REJECT −2.46% under noise | Factor-only metalRough skip w/o ≥8/10 |
| EXP-017 | **KEEP** tip −3.2% (cand −554→−247) | Blind packed LowLevelMesh w/o evidence |
| EXP-018 | REJECT +7.4% | Concurrent texture prefetch w/o 09/10 evidence |
| EXP-019 | REJECT −1.37% under noise | mipmapsMode:.none w/o ≥8/10 |
| EXP-020 | REJECT +7.0% | mapped GLTFAsset(data:) w/o beyond-noise |
| EXP-021 | REJECT +16.6% vs 017 | Index-stream on packed mesh undoing 06/07/08 |
| EXP-022 | REJECT +11.3% | compression:.none w/o 09/10 evidence |
| EXP-024 | REJECT +1.34% | Fused UV float2 w/o ≥8/10 |
| EXP-027 | REJECT −0.92% under noise | none∧none CreateOptions w/o ≥8/10 |
| EXP-028 | REJECT +1.41% under noise | Fused JointInfluences w/o ≥8/10 |
| EXP-029 | **KEEP** −3.30% (03/05/10 −249) | — |
| EXP-030 | REJECT +4.55% regress | No-copy ImageIO bufferView decode w/o 08/09/10 win |
| EXP-031 | REJECT +125.6% (tweak1; was NEAR_MISS −2.56%) | MR swizzle / gray+alpha 16bpp pack dual-delete w/o beyond-noise (10 regress) |
| EXP-032 | REJECT +1.59% under noise | Post-upload session CGImage eviction w/o beyond-noise 09/10 (inverted 9/10) |

## Notes

- After 009, 07 is not the old opacity tax — don’t retarget ARGB ideas at 07.
- Post-cp-002: structural KEEPs done; late EXPs were folklore on the wrong residual. No research without residual-map. VARIANT of REJECT needs new measured evidence.
- Stop 2026-08-20: `reject_only_batches=3`, empty queue → campaign closeout (`PERFORMANCE-OPTIMIZATION.md`). Residual still 09/10 texture-bound.
