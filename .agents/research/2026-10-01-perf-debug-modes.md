# Debug / view-mode performance on big GLBs (2026-10-01)

Scope: why wireframe and the channel modes (normals, UV, base colour, ...) and the skeleton
overlay are slow on big files, per renderer, and the cheapest fixes. Read-only research in
`.worktrees/next-main`; nothing was built or run. "Verified" means read in code or a primary
source. "Assumed" means it needs the harness in section 5 to confirm.

There is **no overdraw mode** in either renderer: `RenderViewMode` is shaded / wireframe /
13 channels (`GLTFCore/RenderViewMode.swift:2-21`). RealityKit also has `lightingDiffuse`,
`lightingSpecular` and vertex colours (`RendererRealityKit/PreviewDebugMode.swift:66-78`).

## 1. Answer first

| # | Renderer | Problem | Cost scales with | Severity |
|---|---|---|---|---|
| 1 | Web | Wireframe rebuilds every edge **on the CPU, every frame** and uploads it | triangles, per frame | Worst: about 1.5 M tris gives multi-second frames; 14 M tris runs out of memory or hangs |
| 2 | RK | Skeleton overlay deletes and rebuilds every bone mesh on **every** RealityView `update` and runs a tree search per joint | joints × nodes, per update | High on rigs (712 joints in the corpus) |
| 3 | RK | Every mode switch walks the whole entity tree 3–4 times and re-sets `ModelComponent` on every model | entities (one per instance) | High on node-heavy files (972 k nodes in the corpus) |
| 4 | RK | Wire / vertex-colour / double-sided copy every material per entity, which breaks the convert's shared-material cache | entities × materials | Medium (assumed: more GPU material state, a pipeline build on first use) |
| 5 | Web | First switch into each channel compiles a new shader program per material permutation, synchronously | unique material define-sets | Medium, once per mode per file |
| 6 | Both | Steady-state GPU: wire draws every triangle edge (both renderers); web wire also draws the full shaded frame underneath it | triangles | Low to medium. This is the real floor. |

Textures are **not** re-uploaded on a mode switch in either renderer. RK material copies keep
their `TextureResource` references. The web page only changes `debugOutput`. Mesh data is not
regenerated in RK either: `.lines` is a material flag, not edge extraction.

## 2. Findings with evidence

### F1 (Web): CPU wireframe rebuilt every frame
- `tick()` calls `view.renderFrame` and then `drawOverlays()` on every rAF while live
  (`RendererWebKit/web-renderer/viewer.html:91-104`).
- `drawOverlays` builds a fresh JS `lines` array every frame. With wireframe on it calls
  `collectWireframe` (`viewer.html:370-378`), which walks every node and every primitive. For
  every triangle it calls `transformPoint` three times (each call allocates an array) and
  `pushLine` three times, which is 36 JS numbers per triangle (`viewer.html:329-368`, helpers
  at 196-207).
- It then runs `new Float32Array(lines)` + `gl.bufferData(..., STREAM_DRAW)` every frame
  (`viewer.html:388-390`).
- Accessor views are cached by Khronos (`getNormalizedDeinterlacedView` memoises
  `normalizedFilteredView`, verified in `gltf-viewer.module.js`). The cost is the loop,
  allocation, GC and upload, not decoding.
- Cost model: about 36 doubles (288 B) of JS array plus 72 B Float32 per triangle per frame.
  Flame Knight (1.5 M tris) gives about 430 MB JS array + 108 MB upload per frame. Warrior_Girl_2
  (14.3 M tris) gives about 4 GB per frame, so it effectively hangs or the WebContent process dies.
- Correctness side-issue: it uses node world matrices and rest-pose positions, so it ignores
  skinning and morphs. It is also hidden-line (depth `LEQUAL` over the shaded frame), while RK
  `.lines` is x-ray.

### F2 (RK): skeleton overlay rebuilt on every update
- `applySkeletonOverlayIfNeeded` runs from the RealityView `update` closure
  (`RendererRealityKit/PreviewScene.swift:373`). When the overlay is already shown it calls
  `updateBones` every time (`PreviewScene.swift:620-635`).
- `updateBones` removes every bone entity, then for each joint:
  - two `GLTFNodeLookup.entity` recursive searches, each O(nodes)
    (`RendererRealityKit/GLTFNodeIDComponent.swift:7-19`);
  - a new `MeshResource.generateBox` and a new `ModelEntity`
    (`RendererRealityKit/PreviewSkeletonOverlay.swift:45-84, 124-148`).
- Because `thickness` is nil on that path, it also runs `jointRadius` → `PreviewCamera.modelBounds`,
  a `visualBounds` walk over every model entity (`PreviewSkeletonOverlay.swift:56, 151-156`;
  `PreviewCamera.swift:368-398`).
- `apply` builds one `generateSphere` mesh per joint instead of sharing one (`:112-121`).
- Cost per update is about 2·J·N entity visits + J mesh generations + one full bounds walk.
  Emma Frost (712 joints, 709 nodes) gives about 1 M visits and 700 box meshes per update.
- `update` is not called per frame (the playback `currentTime` `@State` is never read in
  `body`; `PreviewScene.swift:74, 496`). Two consequences:
  - The cost lands on every unrelated state change: overlay, look, floor, debug mode.
  - The bones do **not** follow animation, even though the doc comment at `:43` says they do.

### F3 (RK): mode switch does several full-tree passes and re-sets every ModelComponent
- `PreviewDebugMode.apply` (`RendererRealityKit/PreviewDebugMode.swift:114-140`) does:
  - `store.restore(root)`: visits every entity and re-sets `ModelComponent` on each one with a
    snapshot (`:186-195`), including channel ↔ channel switches that never changed materials;
  - `clearDebug`: another full walk that removes `ModelDebugOptionsComponent` (`:227-231`);
  - `snapshotIfNeeded`: a third walk (`:176-184`);
  - a fourth walk to map materials or set the debug component (`:205-242`).
- Recursion goes through `entity.children` at every level (`:197-202, 276-283`).
- The convert makes one child entity per instance (AGENTS.md), so entity count is roughly glTF
  nodes plus instances. Warrior_Girl_2 has 972 k nodes / 9 120 mesh instances, so each switch is
  about 4 M entity visits plus about 9 k–18 k component sets on the main actor.
- Apple's docs show the debug component set per entity by recursive traversal, so per-model
  sets are required. The repeated full walks are not
  ([ModelDebugOptionsComponent](https://developer.apple.com/documentation/realitykit/modeldebugoptionscomponent)).
- The guard on `frame.debugApplied` is correct: there is no re-apply without a change
  (`PreviewScene.swift:604-617`).

### F4 (RK): material copies per entity break sharing
- The convert shares one RK material per glTF material
  (`RendererRealityKit/Convert/RealityKitResourceContext.swift:87, 127-132`).
- `mapModelMaterials` copies and mutates each material separately for every entity
  (`PreviewDebugMode.swift:233-258`). Vertex colours allocate a fresh `UnlitMaterial` for every
  material slot of every entity (`:210-212`).
- Assumed (not documented by Apple): each mutated copy is its own engine material. That means
  more uniform/argument state and a possible pipeline build the first time a `.lines` variant
  is used. The texture objects are shared, so nothing is re-uploaded.

### F5 (Web): channel modes compile shaders on first use
- `apply` only sets `params.debugOutput` (`viewer.html:589`). The Khronos renderer maps it to a
  `DEBUG_*` define and selects programs from a cache keyed by the define hash
  (`shaderCache.selectShader` / `getShaderProgram`, verified in `gltf-viewer.module.js`).
- A miss compiles and links synchronously inside `renderFrame`. The bundle does not use
  `KHR_parallel_shader_compile`. The cost is one compile per unique
  (material features × primitive attributes × debug define), the first time each mode is
  visited. After that it is cached for the page's lifetime.
- Assumed magnitude: tens of ms per pbr.frag on ANGLE-Metal, so a 41-material Porsche could
  stall for about 1–4 s per new mode.
- The Swift bridge cost is negligible: one `callAsyncJavaScript("apply")` with the whole look
  (`RendererWebKit/WebRendererHost.swift:165-171`, `WebPreviewCanvas.swift:292`).
  `loadEnvironment` is memoised (`viewer.html:479-495`).

### F6 (Both): steady-state GPU
- RK wire sets `triangleFillMode = .lines` (`PreviewDebugMode.swift:244-258`). This is pure GPU
  work: same vertex work as shaded plus about 3 line segments per triangle, x-ray.
- Channel modes cost about the same per frame as shaded in both renderers (assumed).
- Web renders continuously with no dirty-flag (`viewer.html:91-104`). An idle big model still
  costs a full frame every vsync in every mode. This is not specific to debug modes, but it
  multiplies F1.

### Propagation (verified, cheap)
1. PreviewUI `ViewModeMenu` → `EngineViewportController.setViewMode` →
   `previewSession.viewMode` (`GLTFInspector/Engine/EngineViewportController.swift:153-158`).
2. RK path: the `debugModeIndex` binding (`GLTFInspector/RealityKit/PreviewSession+RealityKit.swift:32-38`)
   → the `PreviewScene` body reads it (`:232`) → `update` → `applyDebugIfNeeded`.
3. Web path: `EngineLookBridge` → `Look` → `PageLook` (`RendererWebKit/WebRendererLook.swift:116-117`)
   → JS `apply`.
4. There is no re-convert, reload or re-open on a mode switch in either path.

## 3. Cost model per mode (dominant term)

| Mode | RealityKit on switch | RealityKit per frame | Web on switch | Web per frame |
|---|---|---|---|---|
| Shaded (from debug) | 3–4 walks O(E) + set ModelComponent for M models | baseline | — | baseline |
| Wireframe | same + material copy per slot (F4) + possible pipeline build | baseline + lines raster | ~0 | **baseline + O(T) CPU + 72·T B upload** |
| Channel (normals, UV, base, ...) | 3–4 walks + M debug-component sets | ≈ baseline | compile P programs (first visit) | ≈ baseline |
| Vertex colours (RK) | walks + M×slots new `UnlitMaterial` | ≈ unlit | n/a | n/a |
| Double-sided (RK) | walks + material copies | baseline, no culling | n/a | n/a |
| Skeleton (RK) | O(J·N) + J meshes, **on every update** | — | n/a (not a web feature) | — |

Key: E = entities, M = model entities, T = triangles, J = joints, N = nodes, P = unique shader
permutations.

## 4. Candidate fixes (cheapest first, inside each renderer)

**W1. Web wireframe via `WEBGL_polygon_mode` (cheapest, largest win)**
- Change: request `gl.getExtension("WEBGL_polygon_mode")` once. When wireframe is on, set
  `polygonModeWEBGL(FRONT_AND_BACK, LINE_WEBGL)` around the Khronos primitive draws and drop
  `collectWireframe`.
- The Khronos post passes (tonemap, blits) draw `TRIANGLE_STRIP, 0, 4` quads, and the
  cubemap/IBL passes `TRIANGLES, 0, 3`. Those must stay FILL. Do this with a small wrapper in
  `viewer.html` around `gl.drawArrays`, not a bundle patch (VERSION says no forking).
- Win: wireframe CPU cost goes from O(T) per frame to about 0. GPU lines come from the shaded
  pipeline, so skinning, morphs and debug channels all stay correct.
- Side effect: x-ray, which matches RK `.lines`.
- Sources: the extension is in the [Khronos registry](https://registry.khronos.org/webgl/extensions/WEBGL_polygon_mode/);
  [web3dsurvey](https://web3dsurvey.com/webgl/extensions/WEBGL_polygon_mode) reports about 98 %
  Safari coverage.
- Risk:
  - The extension may be missing in this WKWebView build. Probe once and keep the fallback.
  - The draw-wrapper heuristic could also hit a primitive authored as a 4-vertex strip.
  - The pixel-diff goldens have no wireframe pose today.
- Measure: page frame time with wireframe on, Flame Knight / Porsche, before and after (harness §5).

**W2. Web wireframe fallback: cache instead of rebuild**
- Change: build the per-primitive line index buffer once per scene (Uint32, 6 per triangle, or
  deduped edges) next to an uploaded position VBO. Per frame, draw each node with a `u_model`
  uniform. Rebuild only on scene or variant change.
- Also hoist the floor geometry out of the per-frame loop.
- Win: CPU per frame goes from O(T) to O(nodes). The one-time build is about the cost of one
  current frame.
- Risk: about 24 B/triangle of GPU memory (345 MB at 14 M tris, so cap it, e.g. skip above about
  5 M tris). Rest pose only, as today.
- Measure: same as W1.

**W3. Web: stop rendering when nothing changed**
- Change: a `dirty` flag set by input, apply, camera, autoRotate, animation or a pending IBL.
  `tick` skips `renderFrame` when it is clean.
- Win: idle GPU/CPU drops to about 0 for every mode.
- Risk: missing a dirty source gives a stale frame. Khronos animations need continuous frames
  while playing. Measure with idle CPU% of the WebContent process.

**W4. Web: soften the first-visit compile (optional)**
- Leave it as is, or after load idle-prewarm the one or two most-used channels (normals, UV) by
  rendering one offscreen frame each.
- Risk: extra load-time work, and it touches the first-GPU-frame budget
  (`.agents/research/2026-09-30-first-gpu-frame.md`). Do it only if the §5 numbers show more than
  about 500 ms.

**R1. RK skeleton: build once, then move**
- Change:
  - Build a `[nodeIndex: Entity]` map once.
  - Share one sphere and one unit-box `MeshResource` plus one material.
  - Create the bones once in `apply`.
  - In `updateBones`, only set `position`/`orientation`/`scale`, and pass the cached thickness.
  - Run it from the existing 16 ms tick while a clip plays (fixes "bones don't follow"), not from
    every `update`.
- Win: per-update cost goes from O(J·N) + J mesh builds to O(J) transform sets.
- Risk: low. Measure with an `updateBones` signpost on Emma Frost.

**R2. RK mode switch: one flat model list, skip no-op restores**
- Change:
  - At load, collect `[(Entity, ModelComponent)]` once, e.g. on `frame` or `DebugMaterialStore`.
  - Restore only when the previous mode changed materials (wire, vertex colours, double-sided).
  - Merge clear and set into one pass.
  - Keep the snapshot dictionary but key it by the flat index.
- Win: 4 × O(E) walks become 1 × O(M). Channel ↔ channel switches skip all `ModelComponent`
  re-sets.
- Risk: the list goes stale on a scene or variant reload. That path rebuilds the scene, so
  rebuild the list there. `PreviewDebugModeTests` (`GLTFInspectorTests/RealityKit/PreviewDebugModeTests.swift`)
  covers restore semantics.
- Measure: wall time of `PreviewDebugMode.apply` per transition on Warrior_Girl_2 / Porsche.

**R3. RK: memoise transformed materials per pass**
- Change: during one `mapModelMaterials` pass, keep the transformed material per original slot
  identity and reuse it, so all entities that shared material K still share one wire copy.
  - The convert's per-glTF-material cache is the natural key. Snapshot indices also work.
  - Use one shared white `UnlitMaterial` for vertex colours.
- Win (assumed): fewer engine materials, so a faster switch and possibly fewer pipeline builds.
- Risk: Swift materials are value types with no public identity. The key has to come from
  convert-side bookkeeping. Measure the switch time, plus first-frame-after-switch via
  `StillRenderer`.

**Not recommended**
- Barycentric or shader wireframes need forking the Khronos shaders or a `ShaderGraphMaterial`
  per material. That is too costly for the win.
- No CreateOptions / mip / off-main re-bench: these are ruled out by AGENTS.md unless a new
  asset class appears.

## 5. Measurement harness

**Corpus.** Bundled samples are small. The only geometry-heavy pinned one is
MetalRoughSpheresNoTextures. Use the user's `RendererTimingBenchTests` set (paths in
`/Users/mattias/dev/glb-preview/GLTFInspectorTests/RendererTimingBenchTests.swift`).
Counts come from parsing the glTF JSON: sum of index counts / 3 × instances.

| File | Triangles | Mesh inst. | Nodes | Mats | Joints | MB | Stresses |
|---|---|---|---|---|---|---|---|
| ~/Downloads/Warrior_Girl_2-2dfbecce.glb | 14.35 M | 9 120 | 972 038 | 9 | 0 | 189 | F1 (OOM), F3 entity walks |
| ~/Downloads/Flame_Knight_…-d3c47b9d.glb | 1.50 M | 15 | 22 | 2 | 0 | 121 | F1, F6 |
| Khronos samples/MetalRoughSpheresNoTextures | 1.04 M | 102 | 119 | 98 | 0 | 0.3 | F1, F5 (98 materials) |
| ~/Downloads/2024_Porsche_992_GT3_R-b76c9b2a.glb | 471 k | 123 | 492 | 41 | 0 | 42 | F1, F4, F5 |
| ~/Downloads/EMMA_FROST_…-b00a8be4.glb | 202 k | 13 | 709 | 12 | 712 | 26 | F2 (only rigged file) |
| ~/Downloads/Jaguar_MK2_…-bcdb3d9c.glb | 44 k | 11 | 34 | 3 | 0 | 13 | control (mid) |
| Khronos samples/Corset, BoomBox | 18 k / 6 k | 1 | 1 | 1 | 0 | 13 / 10 | control (texture-heavy, few tris) |

The Khronos files that are large on disk (Corset, BarramundiFish, BoomBox, SpecGlossVsMetalRough)
are big because of their **textures**, not geometry, so they do not stress these paths. For a
pinned, shareable rig and a node-heavy file, consider adding Khronos `BrainStem`, `Fox`,
`ABeautifulGame` and `Sponza` to `scripts/fetch-test-models.sh`.

**What to time.** Use one in-process Swift Testing suite, gated off by default like
`RendererTimingBenchTests`, printing `mode-bench` lines. Do not use qlmanage (per memory).

1. RK switch cost:
   - Load with `EntityLoader`, then `makeTurntable`.
   - For each transition (shaded→wire→shaded→normals→uv→shaded, plus double-sided on/off), time
     `PreviewDebugMode.apply` and count visits and component sets.
   - Wrap it in `OSSignposter` so Instruments shows the same intervals in the live app.
2. RK frame after switch: time `StillRenderer.capture()` once right after each `apply`, then
   again. The difference approximates pipeline or material build.
3. RK skeleton: on Emma Frost, time `PreviewSkeletonOverlay.apply` and 10 × `updateBones`.
4. Web per-frame:
   - Add a ring buffer in `tick()` timing `renderFrame` and `drawOverlays` separately.
   - Return p50/p95 from the existing `stats()` page function. The `Stats` struct gets two fields.
   - Drive it through `WebRendererHost(.live)` with `apply(look)` per mode, wait about 60 frames,
     then read `stats`.
5. Web first-visit compile: time the first `still()` after `apply` with a new `debugOutput`
   against the second one (`still` calls `renderFrame` synchronously; `viewer.html:646-655`).
6. Run each step three times and report the median. The machine must be idle: run serially,
   not in parallel with other builds.

Pass bars to aim for:
- Web wire frame at or below 1.2× shaded on Flame Knight.
- RK channel↔channel switch under 50 ms on Porsche.
- Skeleton update under 2 ms on Emma Frost.

## 6. Unresolved
- Whether `WEBGL_polygon_mode` is exposed in this macOS 26 WKWebView. Probe
  `gl.getSupportedExtensions()` once.
- Whether RK dedupes identical mutated materials internally (F4 magnitude) and what `.lines` /
  debug visualization pipelines cost on first use. Apple does not document either.
- Real compile ms per Khronos permutation on ANGLE-Metal (F5).
- Host chrome cannot select RK's lightingDiffuse / lightingSpecular / vertex-colour modes, since
  they map to `.shaded` (`PreviewDebugMode.swift:33-40`). This is not perf, but worth a ticket.
