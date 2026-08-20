# What we tried

Search this file **before** creating a dex EXP task. Duplicates are forbidden.
Full rules: [`PROTOCOL.md`](./PROTOCOL.md).

## Champion

| Label | Corpus | sum_median_total_ms | Notes |
|-------|--------|--------------------:|-------|
| **EXP-009** (current) | v2 | **7732.9** | Cutout-as-mask; same-machine control 14677.8; vegetation −89% |
| EXP-006-v2 | v2 | 15332.9 | Packed SIMD (parent) |
| baseline-v2 | v2 | 16387.4 | Frozen immutable baseline (`baseline.json`) |
| baseline-5rep | v1 | 2324.5 | Archived; do not use for new EXPs |

Noise: reject `|delta| < 3%` of champion sum unless ≥8/10 same direction. Prefer same-machine control.

## Tried

| ID | Class | Result | Must not retry |
|----|-------|--------|----------------|
| EXP-000 | cleanup | Removed uncommitted 6s sleep | Re-adding artificial delay |
| EXP-001 | baseline | Informal 3-rep (v1) | Treating as official |
| EXP-002 | skip-required | `includeAnimations: false` | Disabling clips to win bench |
| EXP-003 | skip-required | Skip `makeDocument` (−2.4%, noise) | Skip outliner for tiny/noise gain |
| EXP-004 | skip-required | Skip `prepareGLB` | Shipping prepare skip (VARIANT=cheaper prepare OK) |
| EXP-005 | VARIANT-of-004 (v1) | **REJECT** — prepare never ran; warm bias | Claiming prepare-path win when prepare does not run |
| EXP-005-v2 | VARIANT of EXP-005 | **REJECT** — prepare hits 09 only; isolated “win” 83% non-prepare + slow control; vs frozen −0.59% | Same data-path claim without prepare-only metric / clean control |
| EXP-006 | NEW (v1) | Tentative KEEP −211 ms isolated (stone_wall) | Merging on frozen delta alone |
| EXP-006-v2 | VARIANT (v2) | **KEEP** −1118 ms vs same-machine control (−6.8%); stone/vegetation/cinema | — |
| EXP-007 | VARIANT-of-002 | **REJECT** — warm bias; eagle-only ~−58 ms | Claiming corpus win when non-target files move equally |
| EXP-009 | NEW | **KEEP** −6945 ms vs SM control (−47%); vegetation −89% / cinema flat | Re-adding opacityTexture for detected cutout without fidelity gate |

## Queued (dex)

| ID | Hypothesis | Gate |
|----|------------|------|
| EXP-008 | One ARGB extract → sibling channels | **next** — mecha/animals; not vegetation |
| EXP-010 | convert each GLTFMaterial once per scene | After 008 — leftover after cutout-as-mask may be small |
| EXP-011 | skip unit-square UV wrap + flip alloc | After 008 — vegetation UV tax residual |
| Round research | External docs (profile done) | Before inventing further EXPs |

## Profiler note (vegetation)

07 is slow due to **per-mesh convert**, not file size (≈same tris as cinema, 6.8× slower). 81 factor-1 BLEND cutouts + per-primitive material convert. Do not aim EXP-005/008 at 07.

## Forbidden

- Parallel benchmarks / builds on this machine
- Lower quality, skip textures/meshes, special-case corpus
- Re-running EXP-002/003/004 as if new
- Shipping prepare skip
- Treating v1 deltas as v2 champion wins without re-bench
- Dex task IDs in commits
