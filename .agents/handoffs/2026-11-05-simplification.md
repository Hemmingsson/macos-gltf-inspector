# Simplification sketch — 2026-11-05

Worktree: `.worktrees/simplify` @ bacfa1ad (detached from main).
Epic: `8crg53la` Simplify preview app.
Primary checkout left dirty (unrelated WIP).

## Baseline
`./scripts/dev.sh test` — **RED** (56 issues): AnimatedReference*, AnimationPose*, GLTFValidatorCorpus, MetalRenderer*, ThumbnailRenderer*, PixelDiffMetal* (many), FeatureReference*, PixelDiffCoverage*, TimelineHUD morph. Treat as known until a cut changes the set.

## Modules
- **GLTFCore** — JSON document, validator (JSCore + dart.js), App Group, look vocab
- **Renderer** — one Metal Khronos port; ModelView / ModelCanvas / ThumbnailRenderer
- **GLTFInspector** — window chrome + DesignSystem; dual open (JSON summary ‖ Metal load)
- **PreviewExtension / ThumbnailExtension** — same Renderer, App Group read-only

## Data flow
URL → DocumentWindow: `openSummary` (panels) + `ModelCanvas` (pixels) → validation after canvas ready.
QL/thumbnail: ViewOptions.stored → same Metal stack.

## Cuts
1. **Suspect:** delete turntable export end-to-end (keep PNG export).
EOF
