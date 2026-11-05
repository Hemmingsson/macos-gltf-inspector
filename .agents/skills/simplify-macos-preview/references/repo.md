# glTF Inspector — facts for the simplify loop

Discover the rest from the tree. This file is only stable product constraints and how to
verify — not a target architecture.

## Product (keep)

- macOS 26+ viewer for `.glb` / `.gltf`.
- Document window + Quick Look + Finder thumbnail.
- **One** renderer draws all three surfaces (today: Metal port of Khronos Sample Renderer).
- User can inspect what the file contains (tree, meshes, materials, validation, …) — weigh
  each surface against real use; do not invent DCC tooling.
- Settings live in the App Group; only the app writes; extensions read.

## Layout today (may change if you can defend it)

See `AGENTS.md` / `ARCHITECTURE.md` in the repo root. Typical split:

| Area | Role |
| --- | --- |
| `GLTFCore/` | File JSON model, validator, look vocabulary, App Group, logging |
| `Renderer/` | Draw: canvas, Metal port, thumbnails |
| `GLTFInspector/` | App chrome + DesignSystem tokens |
| `PreviewExtension/` / `ThumbnailExtension/` | QL / Finder |
| `GLTFInspectorTests/` | Unit + Khronos reference images |

`project.yml` (XcodeGen) generates the `.xcodeproj`.

## Verify

```bash
./scripts/dev.sh test
# After renderer / look / overlay / camera changes:
TEST_RUNNER_GLTF_METAL_PARITY=1 ./scripts/dev.sh test -only-testing:GLTFInspectorTests/PixelDiffMetalTests
./scripts/dev.sh run cube    # logs → .build/logs/debug.log
./scripts/dev.sh bench       # optional load / first-still / GPU
```

Expect in logs for a window open: one `open start`, then `open ready|failed`, then
`canvas ready|failed`. No “Modifying state during view update”. Failed loads →
`.failed(message)`, never a stuck spinner.

Reference PNGs: `TestModels/References/` (incl. `Features/`). Diffs:
`/tmp/GLTFInspector-pixel-diff/`. Do not regenerate refs unless the sample is new or the
renderer change is deliberate — and look at the PNGs.

## History to distrust

Names and folders that smell like past lives: WebKit / web-renderer / Filament /
PreviewUI-as-framework / DesignCatalog / `Engine*` / `Seam` / `Shell*` / dual document
models / second renderer settings. Confirm with references before deleting.

## Dex

Board: `.atelier/backlog.jsonl` at the primary checkout (worktree agents should still use
the same board unless the project says otherwise). CLI: `dex` / `backlog`.
