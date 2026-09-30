# What dominates the first GPU frame after `loadGltf`

Champion: `.worktrees/webkit-renderer`. Ledger: `docs/webkit-first-paint-experiments.md`.
Do not implement from this note. Do not retry banned rows. Official npm `@khronosgroup/gltf-viewer@1.1.0` is banned.

## Answer

The first GPU frame is **not** `loadGltf` parse. Image *decode* and `gltf.initGl` walk happen in `parseMs`. The first `GltfView.renderFrame` then does, in one synchronous JS call:

1. **`renderer.init`** — first time only: 1024² MSAA×4 + scatter HDR + picking/hover + RGBA16F main + splat + tonemap flag textures (`internalMSAA` default 4, `floatingPointFramebuffer` default true).
2. **Lazy ShaderCache compile/link** — `pbr.frag` / `primitive.vert` plus `tonemap_main.frag` / `fullscreen.vert`. `getShaderParameter` / `getProgramParameter` force a driver sync. Permutation includes `USE_PUNCTUAL`, `LIGHT_COUNT 2` (key+fill), `TONEMAP_KHR_PBR_NEUTRAL`, and per-material `HAS_*` maps.
3. **Lazy `texImage2D` + `generateMipmap` + VBO/IBO `bufferData`** on first bind (`gltfWebGl.setTexture` / `enableAttribute`). PNG/JPEG/WebP GPU upload is **not** in `loadGltf`.
4. **`clearFrame`** clears every allocated FBO, then `drawScene` (transmission/scatter passes only if those drawables exist). Required fixtures are opaque PBR.

Control still-mode numbers (IBL already applied *before* `load`): tiny **139** / BoomBox **217** / Corset **196**. The ~80 ms textured delta is the upload/mip/extra-permutation floor. The ~140 ms tiny floor is init + compile + tonemap + readback, not triangles.

**Prefer experiments that delete first-frame GPU work.** Moving compile/FBO init into `configure` shrinks `stillMs` but grows `pageMs` / `visibleMs` (current KEEP gate).

## Fact vs Assumption

### Fact — what the clocks wait on

| Clock | Where | Waits on |
| --- | --- | --- |
| `parseMs` | page `load()` | `resources.loadGltf(url)`: fetch, parse, `mikktspace` WASM `init` every load, image *decode*, `gltf.initGl` (no `texImage2D`) |
| `fitMs` | page `load()` | `fitCamera()` CPU (`applyTransformHierarchy` + `fitViewToScene`) |
| `firstFrameMs` | **live `load()` only** | `resize` + `view.renderFrame` + `drawOverlays`. **Zero in still mode.** No IBL join. No `toDataURL`. CPU time until JS returns; compile/link `getParameter` and `texImage2D` typically sync the driver, but a later GPU draw may still be in flight. |
| `loadMs` (Swift) | `WebRendererHost.load` | page `load` command + bridge. Still: parse+fit. Live: parse+fit+**first `renderFrame`**. Then kicks deferred IBL; does not join it. |
| `stillMs` (bench today) | `RendererTimingBenchTests` `.still` | wall from `load()` return → `renderStill()` return. **This is the first model GPU frame in still mode** because still `load()` does not call `renderFrame`. It is **not only** that frame. |

`renderStill()` (Swift) is, in order:

1. `finishEnvironment()` — joins deferred HDR (`setEnvironment` → fetch + `iblSampler.filterAll`). Ledger EXP-002: IBL is off `visibleMs`; **`renderStill` still joins IBL**.
2. page `renderStill`: `renderFrame` + `drawOverlays` + `canvas.toDataURL("image/png")` (GPU readback + PNG + base64).
3. WK script message of that data URI + Swift `Data(base64Encoded:)` + `NSBitmapImageRep`.

After EXP-002, proc-cold `iblMs` ≈ 0 and `load` is 6–32 ms, so **most of the old 50–70 ms IBL work lands inside `stillMs`** unless the background task finishes first (race). Control `stillMs` (139/217/196) was taken when IBL ran in `setEnvironment` *before* `load` — that table is the cleaner “first model frame + PNG” baseline. KEEP-002/010 tables omitted `stillMs`.

Live QL / window first *visible* paint is `visibleMs` (page + IBL-now-0 + `load`, and live `load` already includes `firstFrameMs`). Thumbnail `totalMs` = visible + still.

### Assumption

- Rank among compile vs FBO init vs mip vs PNG inside the 139 ms tiny floor is **unmeasured**. Viewer comment (`viewer.html` live `load`) calls the blank “program link + texture upload”; that matches Khronos lazy paths, not a profile.
- `toDataURL` + IPC + Swift decode is **tens of ms** of `stillMs` and is **not** first-frame generation. Isolating it needs a `gl.finish()` / `readPixels` split, not a KEEP run.
- BoomBox / Corset have no transmission/scatter; the 1024² MSAA/scatter FBOs are allocated and cleared anyway, then unused.

Upstream (readable): [KhronosGroup/glTF-Sample-Renderer](https://github.com/KhronosGroup/glTF-Sample-Renderer) `source/GltfView/gltf_view.js`, `Renderer/renderer.js`, `Renderer/webgl.js`, `Renderer/shader_cache.js`, `ResourceLoader/loader.js`. Vendored minify `Vendor/web-renderer/gltf-viewer.module.js` matches that `renderFrame` → `renderer.init` + `drawScene` shape (2026-08-24 tree: physics, splats, HDR tonemap pass). Context7 has no `@khronosgroup/gltf-viewer` library.

## Six one-change hypotheses (first GPU frame only)

Gate for *this* lane is **`stillMs`** on required fixtures (and live `firstFrameMs` if you add a live bench). Still PNG must stay a lit model (`PixelDiffTests` / `TestModels/References`). One change each.

| # | Hypothesis | Expected `stillMs` | PNG risk | How to test | Size |
| --- | --- | --- | --- | --- | --- |
| 1 | **Skip `generateMipmap` on first bind** — after `loadGltf`, set every `textureInfo.generateMips = false` (or no-op `generateMipmap` in a one-line vendor patch). Default samplers use mip min-filters; force `LINEAR` if needed so sampling stays legal. | BoomBox/Corset **−20 to −80 ms**. Tiny **~0**. Real delete, not a move. | Soft minification at 512. Check PixelDiff vs BoomBox/Corset refs. | One flag in `viewer.html` `load` after `loadGltf`. Compare `stillMs` to control 217/196. | **small** |
| 2 | **Do not allocate the unused FBO farm on first `renderer.init`** — skip 1024² opaque/MSAA/scatter and 1×1 picking/hover/splat until a transmission/scatter/pick drawable exists. Init only main (and tonemap) at canvas size (512 still). | Tiny **and** textured **−15 to −50 ms** (alloc + `clearFrame` of five FBOs). | None for required fixtures if those passes never run. Transmission samples would need the FBOs later. | Vendor `renderer.init` early-return / guards. Confirm `opaqueFramebufferWidth` work is skipped (WebGL texture count / logs). | **big** (vendor `renderer.js` shape) |
| 3 | **`internalMSAA = 0`** in `viewer.html` next to the existing key+fill flags. Default is 4; MSAA buffers are for transmission, not the main pass. | **−5 to −25 ms** on first init; tiny win if #2 is not done. Subset of #2. | Aliasing only on transmission materials. BoomBox/Corset/tiny should match refs. | One assignment. PixelDiff + `stillMs`. | **small** |
| 4 | **`floatingPointFramebuffer = false`**. Default true allocates RGBA16F main + splat HDR and keeps the fullscreen tonemap path on 16F. First frame still compiles `tonemap_main.frag`. | **−10 to −30 ms** (one large `texImage2D` + maybe cheaper tonemap). | Highlight clip / tonemap vs refs (MAE gate 2/255). Key+fill is low dynamic range, so maybe inside budget. | One assignment. PixelDiff first. | **small** |
| 5 | **Skip the fullscreen tonemap pass on the first frame** — draw PBR to the default framebuffer with in-shader `TONEMAP_KHR_PBR_NEUTRAL` and `LINEAR_OUTPUT` off. Avoids compiling `fullscreen.vert` + `tonemap_main.frag` and the extra blit. Restore the pass on frame 2 if live needs it. | Tiny **−15 to −40 ms** (one less program link + blit). Textured similar plus #1. | Color-space / exposure mismatch vs refs if the 2026 path assumes HDR + `tonemapPass`. | One `viewer.html` or thin wrap around first `renderFrame`. PixelDiff. | **small** if a flag exists / first-frame branch; **big** if `drawScene` must be forked |
| 6 | **`maxAnisotropy = 1`** (or skip the anisotropic `texParameterf` in `setSampler` on first upload). Default applies `TEXTURE_MAX_ANISOTROPY` at device max (often 16). | **−5 to −20 ms** on BoomBox/Corset; tiny ~0. | Slightly softer glancing textures. 512 still often within PixelDiff. | One line after context create, or vendor `setSampler` guard. | **small** |

Do **not** combine 2+3 (3 is the cheap slice of 2). If #2 lands, skip #3.

## What not to try

**Ledger Must not retry**

- Peek the whole GLB/JSON before `loadGltf` to decide KTX/Draco (EXP-001).
- Stream the renderer bundle in 64 KB `WKURLSchemeTask` chunks (EXP-004).
- `WKWebsiteDataStore.default()` for compile cache (EXP-006).
- Replace our vendor module with official npm **1.1.0** `dist/gltf-viewer.module.js` (EXP-007). Older dated build; **`stillMs` ~2×**.

**Wrong phase for this question**

- `pageMs` (further tree-shake, stub KTX/Draco, named empty data store, `preserveDrawingBuffer` for context create).
- IBL / HDR / LUT / `setEnvironment` / putting probe back on `visibleMs`. `renderStill` joining IBL is a **measurement confounder**, not a first-frame experiment — fix the clock or race, do not “optimize IBL” here.
- `loadGltf` parse / mesh packing / eager `texImage2D` inside `loadGltf` (moves cost to `parseMs` / `loadMs`; thumbnail `totalMs` unchanged unless overlapped with something else).
- Calling `renderFrame` from still `load()` so `stillMs` becomes “only PNG” — measurement shuffle, same GPU work.
- Precompile / `renderer.init` during `configure` **if you still KEEP on `visibleMs`** — relocates first-frame cost onto the page gate.
- Second `viewer.html`. RealityKit convert for pixels. Combining hypotheses.

**Already rejected families (do not retry unless materially different)**

- EXP-001 peek+inject, EXP-003 QL host reuse as a *first spacebar* win, EXP-004 stream, EXP-005 stub KTX/Draco as a *pageMs* play, EXP-006 `.default()`, EXP-007 npm 1.1.0.

EXP-005 stub-on-decode-miss is still open as a **pageMs** retry, not a first-GPU-frame retry.

## Verify

```bash
cd /Users/mattias/dev/glb-preview/.worktrees/webkit-renderer
./scripts/webkit-first-paint-bench.sh --label LABEL
```

Parent benches. Read `stillMs` (and live `firstFrameMs` if you add it). Required: `tiny.glb`, `BoomBox.glb`, `Corset.glb`. PixelDiff for PNG. One change per label.

## Complexity

First `renderFrame` is a **serial driver-sync chain** (FBO alloc → compile/link `getParameter` → upload/mip → multi-clear → draw → still readback). Triangle count is not the wall (tiny 139 vs BoomBox 217). Biggest delete on textured assets is **mips**; biggest shared floor is **init + compile + tonemap + `toDataURL`**. `stillMs` today is a dirty sum (IBL join race + PNG/IPC).
