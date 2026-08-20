# What we tried

Search this file before proposing an experiment. Duplicates are forbidden.

| ID | Class | Result | Do not retry |
|----|-------|--------|--------------|
| EXP-000 | debug | Uncommitted `Task.sleep(6s)` in `PreviewView.State.loaded` removed before campaign. Not shipping. | Re-adding a sleep |
| EXP-001 | baseline | Informal 3-rep `EntityLoader.load` sum-median **2505.9 ms**. Superseded by official 5-rep `baseline.json`. | Re-baselining the same 3-rep harness as if new |
| EXP-002 | skip-required | `includeAnimations: false`. Sum **2003.5 ms** (−502). Eagle 297→140. Also moved non-animated files (noise). QL plays clips. | Disabling animation convert to win the bench |
| EXP-003 | skip-required | Skip `makeDocument`. Sum **2446.9 ms** (−59, −2.4%). Mixed per-file, within noise. Reverted. | Skipping host outliner snapshot for a <3% maybe-noise gain |
| EXP-004 | skip-required | Skip `prepareGLB` rewrite (file flag). Sum **2143.7 ms** (−362). Loads still succeeded on this corpus. Rejected: skips required Reality/metal-rough rewrite. | Shipping a prepare skip. VARIANT allowed: make prepare cheaper without skipping |

## Official champion (immutable until an experiment is accepted)

5-rep + first still frame (`experiments/baseline.json`):

- `sum_median_total_ms` **2324.5**
- `sum_median_load_ms` **2183.8**
- Noise reject: `|delta| < 3%` of total (~70 ms) unless same direction on 8/10 assets

## Round 1 (in flight, isolated worktrees)

| ID | Class | Hypothesis | Files | Agent |
|----|-------|------------|-------|-------|
| EXP-005 | VARIANT-of-004 | Prepared `Data` → `GLTFAsset(data:)` instead of temp write + re-read | `EntityLoader.swift` | implementer-005 |
| EXP-006 | NEW | `Packed.float2/3/4Array` writes SIMD directly; delete per-vertex `grouped` | `PackedAccessors.swift` | implementer-006 |
| EXP-007 | VARIANT-of-002 | `inputRange` returns accessor min/max/count without `Packed.floatArray` when bounds exist | `AnimationHelpers.swift` | implementer-007 |

## Classified, not running this round

| Proposal | Class | Why not now |
|----------|-------|-------------|
| skip `makeDocument` / QL-only document | DUPLICATE EXP-003 | Already rejected; corpus ≤97 nodes |
| skip peek/prepare-until-fail | skip-required | Same family as EXP-004 |
| sidecar pack skip | NEW | Zero on this GLB-only corpus |
| first-clip-only / skip remaining clips | skip-required | EXP-002 family |
| cap bake at 30 fps | VARIANT-of-002 | Quality tradeoff; try lossless EXP-007 first |
| IBL await before `.ready` | NEW | Primary metric is load+still, not `State.loaded` |
| UV unit-square fast path | NEW | After EXP-006 (same mesh/UV data) |
| `opacityTexture` → cached `.alpha` | NEW | Low on this set (tiny BLEND maps) |
| `firstIndex` ObjectIdentifier map | NEW | Low on this corpus |

## Forbidden

- Lower quality, skip textures, skip meshes, special-case corpus files.
- Parallel agents editing the same champion files.
- Re-running EXP-002/003/004 as if new.
- Shipping a prepare skip.
