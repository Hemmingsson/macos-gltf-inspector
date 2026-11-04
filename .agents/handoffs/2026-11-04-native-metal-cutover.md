# Native Metal cutover: Metal is the default; controls and load speed are still in flight

Snapshot: **2026-11-04**, `/Users/mattias/dev/glb-preview`, branch `main` at `6688d18`. This continues
[the port handoff](2026-11-04-native-metal-port-in-progress.md); read its update block first.

**User intent.** Make the native Metal port the renderer on every surface: the document window,
Quick Look and the Finder thumbnail. Everything must work and look like before; only the
rendering moves to the port. Use parallel subagents. **Hold off on simplification and refactoring**
(the `/simplify` review was stopped on request). The user also asked for a measurement of
Metal against Filament and WebKit, shown as a **Gantt chart** of the bench results.

## State on `main`

| Commit | What |
| --- | --- |
| `88add05` | Native port: 33/33 strict pixel parity, meshopt (vendored meshoptimizer 1.2), KTX2 to ASTC, tangent `w` flip, transmission-texture workaround, NEAREST-magnification transmission sampler |
| `387ef1b` | `RendererRaceBench` races `metal` against `filament` and `webkit` |
| `e1f35d0` | Merge of the draw-ordering branch (see below) |
| `6688d18` | Merge of the default-switch branch: **Metal is now the default for all three surfaces** (see below) |

### Draw ordering (merged, `764740b`)

- Draw lists follow the page: opaque (in `groupBy` order), then transmission, then transparent.
- Transmission and transparent draws use a stable sort on the centroid's view-space depth, and the main pass keeps only `depth <= 0`.
- The prepass draws opaque, then transparent, and clears to `[0,0,0,0]`.
- Unlit draws in the transmission pass write `toneMapInverse`.
- `MetalDrawOrderTests` was added. The 33 parity numbers are identical.
- Known gaps:
  - Instanced BLEND/transmission nodes are sorted per instance; upstream sorts once per node.
  - The attribute-limit key is approximate.
  - The `toneMapInverse` branch is not covered by any parity sample.

### Default switch (merged, `0abc573`, `9767f0a`)

- `CanvasRenderer.backend()` defaults to `.metal`. `GLTF_RENDERER=filament|webkit` remains a dev override, and there is no user setting.
- `RendererWebKit/ThumbnailRenderer.swift` takes the thumbnail render logic out of `ThumbnailProvider`, so the same path can be tested in-process.
- Native host edits:
  - `start()` rebuilds a broken renderer.
  - Load failures map to `.callFailed`.
  - A live `renderStill(nil)` renders at the drawable's size.
  - The backing scale is relaid out when it changes.
- `docs/renderer-backends.md` and `AGENTS.md` pitfall 7 were rewritten for the new default.
- Bundle evidence: each framework is embedded once, appexes have no Frameworks folder, all `@rpath`s resolve, `default.metallib` and the `.metalibl` files are in the bundle, and `codesign --verify --deep --strict` passes.
- Tests added: `CanvasRendererFactoryTests`, `ThumbnailRenderPathTests` and `QuickLookCanvasPathTests`. Full run: 186 tests, with only the known validator failure.
- The branch's edits to `docs/README.md` and `docs/pipeline-web-renderer.md` were **dropped** before merging. Other in-flight work has deleted those files in `main`'s working tree, and the deletion must not be touched.

## In flight: two subagents, each in its own worktree, uncommitted when this was written

| Work | Worktree / branch | Touches |
| --- | --- | --- |
| Controls parity in the native host | `.claude/worktrees/agent-a2febfd11d1e62946`, `worktree-agent-a2febfd11d1e62946` | `MetalCamera`, `MetalOverlays`, `MetalRenderer`, `MetalScene`, `MetalSceneLoader`, `MetalMaterialUniforms`, `ShaderTypes.metalh`, `pbr.metal`, the host |
| Load performance | `.claude/worktrees/agent-a033bd492957a08f9`, `worktree-agent-a033bd492957a08f9` | `MetalEnvironment`, `MetalRenderer`, `MetalImageLoader`, `MetalSceneLoader`, `RendererMetal.h`, `project.yml`, new `Scene/MetalLoadKernels.{c,h}` |

The **controls** brief covers matching the page for:
- fit, reset, orbit, pan, dolly and zoom;
- centring on the authored origin;
- near/far updates on zoom;
- file cameras, scenes and variants;
- wireframe;
- every debug channel, including the checkerboard;
- floor, origin and AABB overlays;
- auto-rotate, LoadInfo and failure semantics.

It also covers the two gaps found later:
- `onZoom` must also fire on programmatic zoom, fit and presets.
- Dragging the window must not orbit; port Filament's fix from `6717289`.

The agent was asked to avoid conflicting with the host edits in `0abc573`.

The **load-performance** brief is to cut load time without changing any pixel. Both branches started at `387ef1b`, before the two merges above, so expect conflicts in `MetalRenderer.swift`, `MetalSceneLoader.swift`, `MetalScene.swift` and the host. When merging, keep:
- the draw-list and sort code from `764740b`;
- the host fixes from `0abc573`.

If a subagent is gone, look at its worktree. Commit or inspect whatever is uncommitted there; don't redo the work.

## Remaining steps, in order

1. Merge both branches into `main` (`git branch --show-current` first) and resolve conflicts as described above.
2. Strict gate, which must show 33/33 and never touches PNGs, the manifest or tolerances:
   `TEST_RUNNER_GLTF_METAL_PARITY=1 ./scripts/dev.sh test -only-testing:GLTFInspectorTests/MetalCameraTests -only-testing:GLTFInspectorTests/MetalSceneLoaderTests -only-testing:GLTFInspectorTests/PixelDiffMetalTests`
   Then run `./scripts/dev.sh test`, also with `-only-testing:GLTFInspectorTests/MetalDrawOrderTests` and the new factory and thumbnail suites.
3. Real-window and surface checks. This is allowed: the user asked for "everything should work", and the memory note `ui-verification-xcuitest` permits XCUITest and taking focus. On `main`, run `./scripts/build.sh`, then open the `/Applications` app on several glbs and check:
   - One "open start" and one "open ready" in the log, with no Modifying-state warnings (AGENTS pitfall 8).
   - The badge reads "Metal · Khronos 863b981".
   - Fit, reset, zoom percent, orbit, pan and window drag.
   - Wireframe, debug channels, floor, origin and selection boxes.
   - Scenes and variants, auto-rotate, Export PNG size, resizing, and moving between displays.
   - Quick Look with the spacebar on glb and on gltf with sidecar textures. Do not use `qlmanage`; it hangs headless.
   - Finder thumbnails for a folder, the "Metal" stamp, and the poster cache in the App Group container.
   - That the sandboxed appexes actually load RendererMetal and GLTFKit2.
4. Thumbnail memory. The first Metal thumbnail added about 173 MB to the process footprint: device, library, IBL plists and textures, and the 1024² MSAA transmission targets. WebKit used to carry that cost in its own process. Check for jetsam on a large folder. Possible fixes: free the plist `Data` after upload, and use smaller transmission targets for stills.
5. Re-run the bench alone, on an idle machine: `GLTF_BENCH_RUNS=3 ./scripts/dev.sh bench`. The table goes to `.build/bench/<stamp>.txt`.
6. Build the **Gantt chart** the user asked for. Show per renderer and per file `load` then `still` as consecutive bars, plus `proc-cold` (start, then first still). Show before and after the load-performance work.
   - Baseline table: `.build/bench/20261104-080153.txt`.
   - Parsed JSON: `/private/tmp/claude-501/-Users-mattias-dev-glb-preview/b8e4dcc1-b913-43eb-829c-dbb3b06fc100/scratchpad/race-baseline.json`. It lives in `/tmp`, so copy it if needed.
7. Remove the agent worktrees once merged (`git log main..<branch>` should be empty), and update this handoff.

## Baseline bench (before load optimisation, 37 files raced by all three, median of 3 runs)

| Renderer | Cold start → first still | Median load | Median still | Corpus total |
| --- | --- | --- | --- | --- |
| Filament | 30 → 126 ms | 1 ms | 9 ms | 0.9 s |
| WebKit | 498 → 713 ms | 14 ms | 12 ms | 2.3 s |
| Metal | 1 → 39 ms | **94 ms** | 12 ms | **14.5 s** |

For BoomBox, Metal's load takes 1497 ms against Filament's 48 ms. That is what the load-performance branch has to fix.

## Do not

- Do not simplify or refactor yet, and do not delete Filament: the user said to wait.
- Do not touch the other uncommitted work in `main`: the menu, toolbar and DesignSystem edits, `GLTFInspector/MenuSymbol.swift`, the deleted docs, and `.seecode/`.
- Do not fix the failing `GLTFValidatorCorpusTests` (`ui-showcase.glb: SKIN_SKELETON_INVALID`) as part of this work. It existed before the port and is unrelated.
