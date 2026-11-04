# Native Metal cutover: COMPLETE on main

Snapshot: **2026-11-04**, `/Users/mattias/dev/glb-preview`, branch `main` at `cce3d16`.
Continues [the port handoff](2026-11-04-native-metal-port-in-progress.md).

**User intent (done).** Native Metal is the renderer on the document window, Quick Look and the
Finder thumbnail. Behaviour matches the page; only the rendering backend moved. Filament /
WebKit remain as `GLTF_RENDERER=` overrides. Simplification / Filament deletion still held.

## Final state on `main`

| Commit | What |
| --- | --- |
| `88add05` | Native port: 33/33 strict pixel parity |
| `387ef1b` | `RendererRaceBench` races metal / filament / webkit |
| `e1f35d0` / `764740b` | Draw ordering (opaque → transmission → transparent, centroid depth) |
| `6688d18` / `0abc573` | Metal default on all three surfaces |
| `10738a4` / `0f56307` | Load performance (one decode/image, C kernels, shared environment) |
| `4a526bf` / `56452c5` | Controls parity (`MetalUserCamera`, overlays, onZoom, window-drag orbit fix) |
| `eccf5e1` | Draco thumbnail framing + missing-tangent debug channel |
| `12cb015` | Thumbnail memory: free IBL plist after upload; ≤256 stills use matching transmission targets |
| `f0b38cf` | Overlay soft depth (floor / gizmo / AABB behind the model) |
| `cce3d16` | Stray blank line from controls worktree |

## Verification (this cutover)

- Strict gate `TEST_RUNNER_GLTF_METAL_PARITY=1` PixelDiffMetal + MetalCamera + MetalSceneLoader: **33/33**, exit 0.
- MetalDrawOrder / CanvasRendererFactory / ThumbnailRenderPath / QuickLookCanvasPath / KhronosMetalRendererHostTests: exit 0.
- `./scripts/build.sh` → `/Applications/glTF Inspector.app`: badge **Metal · Khronos 863b981**; one open start + one open ready per file; no Modifying-state warnings; Fit / Zoom / Reset / Export PNG / resize / QL Spacebar (no qlmanage) / Metal-stamped Finder thumbnail OK.
- Left for human eyes: orbit / pan / window-drag feel, wireframe+debug channel chrome, scenes/variants, auto-rotate, multi-display; App Group `posters/` was empty in that verify pass (may need a fresh Finder folder browse).

## Bench: before → after load optimisation

Tables: `.build/bench/20261104-080153.txt` (before) → `.build/bench/20261104-090715.txt` (after, `12cb015` era).
Parsed: `.build/bench/race-baseline.json`, `.build/bench/race-before-after.json`.
Gantt: fine-tune widget in the completing chat (phase before/after, focus summary / BoomBox / slow8 / proc-cold).

| Renderer | Cold → first still | Median load | Median still | Corpus total (37) |
| --- | --- | --- | --- | --- |
| Filament before | 30 → 126 ms | 1 ms | 9 ms | 0.9 s |
| Filament after | 26 → 129 ms | 1 ms | 9 ms | 0.8 s |
| WebKit before | 498 → 713 ms | 14 ms | 12 ms | 2.3 s |
| WebKit after | 776 → 1007 ms | 7 ms | 11 ms | 1.8 s |
| **Metal before** | 1 → 39 ms | **94 ms** | 12 ms | **14.5 s** |
| **Metal after** | 2 → 14 ms | **8.3 ms** | 11 ms | **1.3 s** |

BoomBox Metal load: **1497 ms → 59 ms** (Filament ~47–48 ms).

mtl.thumb.cold BoomBox: **1329 ms → 67 ms**.

## Worktrees

Removed after merge (ahead empty / equivalent cherry):
`agent-a033bd492957a08f9` (load-perf), `agent-a2febfd11d1e62946` (controls),
`agent-a1431d83420d62337` (default-switch), `agent-a8c5237358a660dbc` (draw-order).

Left alone (unrelated): other `.claude/worktrees/*`, `filament-*`, `.worktrees/simplify`.

## Still out of scope (do not touch as part of this cutover)

- Uncommitted menu / toolbar / DesignSystem / `MenuSymbol.swift` / deleted docs / `.seecode/` on main.
- `/simplify` and Filament deletion (user hold).
- Known `GLTFValidatorCorpusTests` (`ui-showcase.glb: SKIN_SKELETON_INVALID`).
- Draw-order gaps: per-instance BLEND sort, approximate attribute-limit key, `toneMapInverse` parity sample.
- Thumbnail footprint still ~196 MB delta on first opaque cube (device + metallib + IBL textures); transmission peak for ≤256 icons is much smaller than 1024² MSAA.

## Remaining optional follow-ups (not blocking cutover)

1. Human pass on orbit / pan / window-drag and multi-display.
2. Confirm Finder poster cache writes under the App Group after a real folder browse.
3. Further thumbnail memory (shared device/library across appex lifetime; optional smaller IBL for stills).
