# Time to first pixel: Quick Look, window, thumbnail × RealityKit / WebKit

Read-only research on `next-main` (`d205dfce`). Nothing was built or run. Every number here comes
from `docs/webkit-first-paint-experiments.md` (WebKit, 2026-09-30) or `docs/pipeline-gltf-to-realitykit.md`.
**There is no RealityKit TTFP number anywhere in the repo.** Paths are relative to the worktree.

## Answer

- **WebKit, every surface:** the cost is the page, not the model. Session-first `pageMs` is about
  1170 ms (WebContent launch plus 3.2 MB module compile). Process-cold `pageMs` is 200–460 ms.
  `loadGltf` is 6–32 ms. The first `renderFrame` (shader link, texture upload, FBO init) adds
  roughly 140–220 ms. EXP-002/009/010 already took the cheap wins. The open lever is **perceived**
  time, and the poster that EXP-008 added is never actually seen (§Finding 1).
- **RealityKit, every surface:** the cost is `RealityKitConvert.build` on the **main actor**. That
  covers meshes, every texture decode and `TextureResource` upload, and every clip, all serial
  before the first frame. The thumbnail then loads the HDR/IBL **after** convert, also serially.
  Quick Look shows only a spinner, with no poster.
- **Progressive loading fits RealityKit best.** Textures go in via `TextureResource.replace`, and
  IBL already arrives after the first frame. For WebKit it means a native poster/proxy while the
  page boots. In-page progressive texturing would need a fork of the vendored Khronos loader, which
  is forbidden.

## Finding 1 (likely bug): the Quick Look poster is hidden behind opaque loading chrome

`WebCanvasController.attach` (`RendererWebKit/WebPreviewCanvas.swift:192-215`) stacks the views as
placeholder, then web view, then loading chrome (`positioned: .above`). `WebCanvasLoadingChrome`
paints `.background(Color(nsColor: .windowBackgroundColor))` over the whole frame (`:31-33`), and
it is hidden only in `revealLive` (`:366-372`), which also hides the placeholder. So the cached
Finder icon (EXP-008, `QuickLookWebKit.swift:52-53`) is covered for the entire time it should be
showing. To verify, take a screenshot of the Quick Look panel while it loads on a file that
already has a Finder thumbnail.

## Finding 2 (suspected bug): a look change during page start can leave the window spinning forever

`reload` sets `loaded = url` before its task runs (`WebPreviewCanvas.swift:248-251`). If the look
changes while `host.start()` is in flight, `work?.cancel()` (`:253`) kills the task that would call
`load`. The replacement task sees `modelChanged == false`, so it only calls `apply` and never loads
or reveals (`:286-306`). In the window, `openSummary` calls `adopt` →
`applyConvertedLighting(dimStudioForFileLights: !lights.isEmpty)`
(`DocumentWindowModel.swift:188-194`). That changes `RenderLook.usesFileLights`
(`GLTFCore/RenderLook.swift:27`) in the middle of the start for any file with
`KHR_lights_punctual`. No test covers a look change mid-load. To verify, open
`punctual-lights.gltf` on WebKit and look for `viewport ready`.

## Timelines (the → arrows mark serial steps)

### (a) Quick Look

**WebKit** (`PreviewExtension/QuickLookWebKit.swift`)
1. `loadView` builds `WebRendererHost(.live)` and starts `start()` (EXP-009, `:14-40`). The page
   loads via the scheme handler. Each resource is a `Data(contentsOf:)` **on main**
   (`WebRendererResourceHandler.swift:41-46`): module 3.3 MB, `libktx.wasm` 1.7 MB, Draco, mikktspace.
2. `viewer.html` runs two classic scripts (libktx, Draco wrapper, `:28,36`), imports the module,
   creates a WebGL2 context, `GltfView`, the resource loader, then posts `ready` (`:684`).
3. In parallel, `preparePreviewOfFile` returns at once (Apple: "The operating system shows a
   loading spinner, so call the handler as soon as possible"). It installs the canvas with the
   cached icon from `NSWorkspace.icon(forFile:)` on main (`CachedQuickLookThumbnail.swift:18`).
4. `reload` (`WebPreviewCanvas.swift:254-306`): JSON peek detached → `await start()` → `apply(look)`
   (only records the HDR) → `open`. In the page that is `loadGltf` (fetch `/model`, a main-thread
   `Data(contentsOf:)` of the **whole file**; parse; mikktspace; image decode), then `fitCamera`,
   then the **first `renderFrame` inside `open`** (`viewer.html:557-565`).
5. `revealLive` shows the pixels. IBL starts after that (`:567`) and lands a frame or two later.

Clocks: `visibleMs` ≈ page + load. Session-first is about 1850 ms before EXP-002, and process-cold
is 230–260 ms (KEEP-002 table).

**RealityKit** (`QuickLookRealityKit.swift`)
1. `loadView` shows a SwiftUI `ProgressView`. There is **no poster** (`:16-32`).
2. `preparePreviewOfFile` starts a detached task and returns (`:44-55`).
3. `EntityLoader.load` (`EntityLoader.swift:65-97`), off main: `GLBBox.peekJSON`, the sidecar check
   and `makeDocument` (a sidebar document that Quick Look never shows), then `GLTFAsset(url:)`
   (GLTFKit2 parse, Draco), `SpecGlossBake`, the animation filter.
4. **Main actor:** `RealityKitConvert.build` (`Convert/RealityKitConvert.swift:59-97`). Nodes,
   meshes and materials convert, with lazy `newCGImage` decode, optional cap, and the sync
   `TextureResource(image:)` (`RealityKitResourceContext.swift:208-227`). Then **all clips**
   (`:84-95`, `includeAnimations: true` in Quick Look).
5. `present`, then `RealityPreviewCanvas` → `RealityView` make (`PreviewScene.swift:236-305`):
   turntable, floor, camera, key+fill lights (`PreviewLighting.swift:52-54`). First frame.
6. `onAppear` → `prefetchLook` (`PreviewScene.swift:430-433,572-584`) →
   `PreviewLighting.loadEnvironmentResource`, which is `@MainActor`. `EquirectangularImage.load`
   is a **sync float HDR decode on main** (`PreviewLighting.swift:144-163`), followed by
   `EnvironmentResource(equirectangular:)`. The IBL swaps in on a later `update`. Every Quick Look
   process redoes this because the cache is static per process (`:59-62`).

### (b) App window

**Shared:** `DocumentWindowModel.beginOpen` logs `open start` and **immediately** starts the
Khronos validator (`DocumentWindowModel.swift:120-121,208-236`). It runs on a utility queue with a
new `JSContext`, evaluates the whole `gltf_validator.dart.js`, and base64-encodes the whole file
(up to 48 MB) (`GLTFCore/GLTFValidator.swift:107-190`). The doc comment says "call after first
paint" (`:62`), but the code does not. The validator competes for CPU with convert or page compile.

**WebKit** (`GLTFInspector/WebKit/WebDocumentWindow.swift`): `onAppear` → `beginOpen` and
`openSummary` (JSON peek, detached, `GLTFCore/GLTFDocumentSummary.swift:47-55`). In parallel, the
canvas mount creates a **new** host in `attach` (`WebPreviewCanvas.swift:198`). The page starts
only once SwiftUI mounts the canvas. After that it follows QL steps 2–5, but with no placeholder
(`:48`).

**RealityKit** (`GLTFInspector/RealityKit/RealityDocumentWindow.swift:137-186`): `beginOpen` →
`EntityLoader.load` (as QL steps 3–4) → `RealityClipPlayer(model:)` (clip duration probes on main),
`adopt`, `open ready` log → `HostPreviewContainer` → `RealityPreviewCanvas` make → first frame →
IBL as in QL step 6. `open ready` fires **before** the first frame, so it does not measure TTFP.

### (c) Thumbnail

**WebKit** (`ThumbnailExtension/ThumbnailWebKit.swift`): renders are serialized on one warm
`WebRendererHost(.still)` per process (`:22-31`).
- **Cold:** `start` → `apply` → `load` (still mode: parse and fit, no frame) → `still`, which does
  `await loadEnvironment()` (HDR fetch plus `iblSampler` prefilter, **serial after load**), then
  `renderFrame`, then `toDataURL` → base64 → Swift `Data` → file.
- **Warm:** about 70 ms per file (`:10-11`), with the IBL already cached in the page.

**RealityKit** (`RealityThumbnail.swift:11-24`): `loadThumbnail` (parse off main, convert on main,
`maxTextureEdge: 1024`, no clips) → `makeTurntable` → `StillRenderer.build`: `MTLCreateSystemDefaultDevice`,
a **new `RealityRenderer()` per icon**, then `await prefetchLook` — **HDR decode and
EnvironmentResource are serial after convert** (`StillRenderer.swift:158-181`) → `updateAndRender`
→ `getBytes` → CGContext → `PNGWriter`. Only the total is logged (`ThumbnailRealityKit.swift:15-21`).

## What is serial that could be parallel, on main, or redone

| Item | Where | Kind |
| --- | --- | --- |
| RK convert: texture decode, upload and clip build | `RealityKitConvert.swift:59-97` | main, serial, before first frame |
| RK HDR decode | `PreviewLighting.swift:144-163` | main and sync. Redone per process |
| RK thumbnail IBL after convert | `StillRenderer.swift:171` | serial. Could start at t0 |
| RK `RealityRenderer()` per icon | `StillRenderer.swift:163` | redone per request (cost unmeasured) |
| RK QL builds the sidebar document, stats and debug modes | `EntityLoader.swift:74,187-207` | unused work in Quick Look |
| Validator at open start | `DocumentWindowModel.swift:121` | competes for CPU with first paint |
| WK scheme handler file reads | `WebRendererResourceHandler.swift:43-46,102` | main. Model read starts only when the page asks |
| WK still IBL after load | `viewer.html:567,646` | serial in still mode, where `still` waits for it anyway |
| WK window host made at mount | `WebPreviewCanvas.swift:198` | measured as not worth a spare host (pipeline doc) |

## Ranked candidates (one change each, none on a must-not-retry list)

| # | Change | Expected win | Risk | Measure |
| --- | --- | --- | --- | --- |
| 1 | **Show the poster:** when a placeholder exists, give the loading chrome a clear background and turn it into a small corner pill (WK QL). | Perceived TTFP drops from 230–1850 ms to about 20 ms on files Finder has thumbnailed. | Low. Framing differs (icon is front-¾ on grey, live is front), so cross-fade. | QL screenshot sequence; new `ql poster shown` marker |
| 2 | **Fix Finding 2:** in `reload`, track "loaded" only after `load` succeeds, or make a look-only task load when `!didRevealLive`. | Infinite becomes normal on WK window with file lights. | Low | `WebCanvasControllerTests`: look change during `start` must still reach `.ready` |
| 3 | **RK: deferred textures.** First `build` gives each texture a 1×1 (or ≤128 px ImageIO-thumbnail) `TextureResource`. After the first frame, decode full size and `TextureResource.replace(withImage:options:)` (macOS 12, `@MainActor`, blocking, *same resource*, so no material reassign). Window and QL only. Thumbnails keep final pixels. | For texture-heavy files, TTFP drops by most of convert. Unmeasured. Decode plus upload is the bulk of `build` on textured assets (assumption). | Medium. Visible pop-in. Alpha-usage probe (`alphaUsage`) needs the real image, so keep a CPU decode for BLEND/MASK base colour, or defer that material. Not the banned "off-main decode": it *moves work after first paint*, it does not parallelize it. | Signposts around texture work in `build`; `rk first frame` vs `rk textures final` |
| 4 | **RK thumbnail: start IBL at t0.** Kick `PreviewLighting.prefetchLook` concurrently with `loadThumbnail`, and make `EquirectangularImage.load` nonisolated (off main). | First icon per process saves min(convert, IBL). Later icons save about 0 (cache). | Low | `thumbnail ready realitykit` ms, first versus second file per process |
| 5 | **RK QL/window: HDR decode off main, started at open** (not `onAppear`). | No first-frame pixel win. Removes a main-thread hitch right after first paint, and IBL lands earlier. | Low | Main-thread gap (`Instruments › Hangs`) after `rk first frame` |
| 6 | **Defer validation** until canvas `.ready` (both renderers). Matches the doc comment. | Large files: less CPU and memory contention (base64 of up to 48 MB plus JSC script eval). | Low. The panel shows the result slightly later. | `open start` → first frame, with and without, on a ≥20 MB GLB |
| 7 | **RK: clips after first frame** in QL and window (two `build` phases: meshes, then clips in their own `GLBTry`, already separate at `:84-95`). | Animated files: TTFP drops by clip convert time. | Medium. Clip 0 paused poses the model on its first frame (tidy-realitykit note), so the pose would snap once. | `rk first frame` on BoxAnimated / Fox |
| 8 | **Own poster cache:** the thumbnail extension also writes its PNG to the App Group container (both extensions have the group, `*.entitlements`), keyed by path, size, mtime, renderer and look hash. QL and window show it at once, for both renderers. | Like #1, but larger, matching the renderer, and present for RK QL too. | Medium. Staleness, disk cap, privacy (same class as Icon Services). | Hit rate plus `poster shown` uptime |
| 9 | **Native JSON proxy:** while the page or convert runs, draw floor plus bounding box from `ModelBounds`/`GLTFDocumentSummary.bounds` in SwiftUI, renderer-neutral. | Something on screen about 10 ms after open for *uncached* files. | Low–medium. Product call: a box may read as "broken". DESIGN.md. | Screenshot |
| 10 | **WK: prefetch model bytes during page start.** When the URL is known (QL `prepare`, window `onAppear`), read the file off main into the handler, then serve `/model` from memory. | Large or cold-disk files: hides the read inside `pageMs`. Small files: about 0. | Low–medium. Memory spike, so cap by size. Differs from the rejected "off-main / mapped read", which measured the main gap and not overlap with page start. | `viewport ready` − `page start ready`, 256 MB GLB, purged cache |
| 11 | **WK still mode: start IBL at `apply`** (still pages only; live keeps EXP-002). | Only the first icon per thumbnail process. | Low | Cold thumbnail `totalMs` |
| 12 | Retry **EXP-005** (lazy KTX/Draco) using flags Swift already has from its JSON peek. | `pageMs` −5 to −10 % measured before. Under the 12 % gate. | Medium | Ledger gate |
| 13 | RK: reuse one `RealityRenderer` per thumbnail process. | Unknown. Measure `RealityRenderer()` first. | Low | Signpost around `StillRenderer.build` |

**Do not re-propose:** any must-not-retry row in the ledger; EXP-011..016 GPU flags; the shared
data store; the spare warm host; off-main or mapped reads as a main-gap fix; the CreateOptions /
mip / Metal-upload / off-main-decode family for RealityKit; a second `viewer.html`; forking the
Khronos loader for in-page progressive textures.

## Progressive design sketch

**WebKit (QL / window):** t0 shows the poster (cached icon, or #8 cache) under a transparent status
pill, or the #9 JSON proxy on a miss. At page `ready`, keep the poster. `open` returns after the
first frame (key+fill), then cross-fade the poster out over about 150 ms. When IBL lands (already
async), the image re-lights in place. Animations and panels are unchanged. Everything in the page
stays the same, apart from optional #11 for still mode.

**RealityKit (QL / window):** t0 shows the poster (#8, or the icon via `NSWorkspace`; move
`CachedQuickLookThumbnail` somewhere both renderers can link without WebKit) under the spinner.
Phase 1, on main, builds meshes and factor-only materials with 1×1 textures, reusing the material
cache, and the first frame shows key+fill. Phase 2 (`Task` after first frame, yields between
images) decodes and `replace`s each texture, largest first. Phase 3 brings in the IBL resource
(prefetched since t0, #5). Phase 4 builds the clips (#7). Thumbnails take one shot (final textures),
with the IBL started at t0 (#4).

## Measurement plan

**Existing markers.** `open start` / `open ready` carry `uptimeMs` (`DocumentWindowModel.swift:120,198`;
`RealityDocumentWindow.swift:196`). WK also logs `page start begin/ready pageMs`
(`WebRendererHost.swift:129-145`), `viewport attach/adopt/ready … firstFrameMs`
(`WebPreviewCanvas.swift:184,201,302-305`), `thumbnail ready … ms` (both renderers) and `ql renderer`.
RK has no first-frame or Quick Look ready marker. `AppLog` is `os.Logger` only, with no signposts
(`GLTFCore/AppLog.swift`). It allocates an `ISO8601DateFormatter` per line when the file sink is on.

**Add** an `OSSignposter(subsystem: AppLog.subsystem, category: .pointsOfInterest)` in `GLTFCore`,
with intervals `open` (open start → first visible frame), `page`, `parse`, `convert.meshes`,
`convert.textures`, `convert.clips`, `ibl`, `still`, and events `poster shown`, `first frame`,
`final look`. The RK `first frame` comes from a `SceneEvents.Update` subscription in the
`RealityView` make, taking the first update after `content.add` (an assumption: that update is
the first rendered frame, so check it against a screen recording). The QL markers need a
`ql prepare` uptime log. For the WK page, `parseMs`, `fitMs` and `firstFrameMs` already return in
`LoadInfo`.

**Bench.** `RendererTimingBenchTests` and `scripts/webkit-first-paint-bench.sh` were removed from
`next-main` (`68328b05`). `AGENTS.md:44` still lists the test. Restore it from history for WK
clocks. For RK, add an equivalent in-process loop over tiny / BoomBox / Corset plus one ≥20 MB
textured GLB and one animated GLB, recording `convert.*` and `first frame`. Gate as the ledger does
(≥12 % on BoomBox and Corset, tiny ≤ +15 %). Measure perceived wins (#1, #8, #9) with
`poster shown` uptime and screenshots, not the bench.
`qlmanage` hangs headless, so use the in-process tests or XCUITest per memory.

## Unresolved

- How RK convert time splits across meshes, textures and clips. This is the gate for #3 and #7,
  so measure it first.
- Whether `TextureResource.replace` on many textures in one frame hitches. Spread it over frames.
- Whether a never-thumbnailed file has a Finder icon at all in a fresh QL process (EXP-008 says a
  cache miss gives no placeholder). If not, #9 is the only cold-file option.
- Findings 1 and 2 come from reading the code and have not been run.
