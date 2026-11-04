# glTF → pixels (Khronos Sample Renderer in WebKit)

How a file becomes pixels. Every surface uses the same page
(`RendererWebKit/web-renderer/viewer.html`) inside a `WKWebView` owned by `WebRendererHost`.
All of it lives in the extension-safe `RendererWebKit` framework; the page ships once, inside
`RendererWebKit.framework`, and is found with `Bundle(for:)`. The HDRs come from `GLTFCore`
(`KhronosEnvironments.bundledURL`, served by name at `/environments/<stem>.hdr`).

The page loads the file itself. The window's panels read the file's JSON
(`GLTFDocumentSummary`), so the sidebar describes the file, not what a renderer kept.

---

## When to read this

| You need | Go here |
| --- | --- |
| Why a web renderer, and why Khronos | [Why this renderer](#why-this-renderer) |
| What the page draws, and how Swift drives it | This file |
| What a control actually changes on screen | [What changes the picture](#what-changes-the-picture) |
| How to catch a renderer regression | [`../TestModels/References/README.md`](../TestModels/References/README.md) |
| Update the vendored Khronos bundle | [Vendored bundle](#vendored-bundle) |

---

## Why this renderer

glTF Inspector is a pre-flight tool for people working with glTF **for the web**: check what a
file contains and how it renders before opening it in Blender or wiring it into a project.
Fidelity is the product, so the renderer is the reference one: the
[Khronos glTF Sample Renderer](https://github.com/KhronosGroup/glTF-Sample-Renderer)
(Apache-2.0). It renders every `KHR_materials_*` extension as authored (transmission, volume,
iridescence, anisotropy, dispersion, sheen, specular, spec-gloss), plus
`KHR_materials_variants`, `KHR_animation_pointer` and `KHR_texture_basisu`, with no rewrite of
the file first. It also ships the debug output channels behind the view modes.

One hard constraint shapes the rest: **window, Quick Look and Finder thumbnail use the same
renderer.** A file must not look one way in Finder and another when opened. A `WKWebView`
renders WebGL inside the sandboxed, non-UI `QLThumbnailProvider` once the extension has
`com.apple.security.network.client` (see [Stills](#stills-and-the-thumbnail-reply)).

Against three.js (prototyped 2026-08-24, same file and machine) the Khronos renderer parsed
glTF 5–10× faster (11–23 ms vs 114–122 ms) and reached a first frame from a cold process
sooner (490–535 ms vs 557–581 ms); its cost is a one-time shader compile per process. Vendor
from git — the npm package is stale.

Costs, measured once: a cold thumbnail through the real sandboxed extension takes ~1.8 s for a
10–13 MB file (thumbnails are async and cached), and the WebKit process family is ~430 MB RSS
showing BoomBox.

---

## Surfaces

| Surface | Swift side | Mode | Look |
| --- | --- | --- | --- |
| Document window | `DocumentWindow` → `WebPreviewCanvas` + `WebCanvasController` | `.live` | the window's viewport (`EngineLookBridge`) |
| Quick Look preview | `PreviewViewController` (prestarted host) | `.live` | `Look.stored(showsFloor: true)` |
| Finder thumbnail | `ThumbnailProvider`, one warm `WebRendererHost` per process | `.still` | `Look.stored()` |

`.still` never adds the web view to a window. Pixels come from `canvas.toDataURL()` —
required for non-UI `QLThumbnailProvider`. `.live` runs a `requestAnimationFrame` loop in the
hosted view.

---

## Bridge

```mermaid
flowchart LR
  disk[".glb / .gltf on disk"] --> handler["WebRendererResourceHandler"]
  bundle["web-renderer/ + GLTFCore HDRs"] --> handler
  handler --> page["viewer.html"]
  host["WebRendererHost.call"] -- "callAsyncJavaScript: open / apply / camera / still / stats" --> page
  page -- "push: ready / warning / contextlost / error" --> host
  page --> khronos["GltfView / GltfState"]
```

1. `WebRendererHost.start()` loads `gltf-inspector:///viewer.html?mode=still&size=512` (or
   `mode=live`). Mode and still size are read once, from the URL; the page posts `ready`.
2. `WebRendererResourceHandler` (`WKURLSchemeHandler`) serves the page, `libs/`, LUTs,
   `/environments/*.hdr`, and the model at `/model/<name>` (plus sidecar siblings for `.gltf`).
3. Swift calls five async page functions through one generic `call(fn, arg)`: the argument is
   `Encodable` JSON, the result is decoded from JSON, a JS throw becomes
   `WebRendererError.callFailed("<fn>: <page message>")`.

   | Page function | Swift | Returns |
   | --- | --- | --- |
   | `open({url})` | `load(model:)` | `LoadInfo` (triangles, meshes, timings, canvas size) |
   | `apply(look)` | `apply(_ look:)` | nothing; the whole `PageLook` |
   | `camera({op})` | `camera(.fit / .orbit / .pose / .get)` | `RendererCameraState` (pose + scene bounds) |
   | `still({size})` | `renderStillPNG(size:)`, `renderStill(size:)` | PNG data URL |
   | `stats()` | `stats()` | canvas size, triangles, page background (diagnostics, tests) |

4. The page pushes only events, never replies: `ready`, `warning` (every Khronos
   `console.error`, logged as `page warning`), `contextlost` and `error` (outside any call).
5. The store is a non-persistent `WKWebsiteDataStore`. Nothing is fetched from the network.

The Khronos renderer rejects **absolute** library and LUT URLs. Paths on the page stay
relative to the scheme root. Classic scripts before the module, or construction throws:
`libs/libktx.js` (global `createKtxModule`) and `libs/draco_wasm_wrapper_gltf.js` (global
`DracoDecoderModule`, which the sample viewer would otherwise fetch from a CDN).

---

## Look

The look is one value, `WebPreviewCanvas.Look`: the settings-level `GLTFCore.RenderLook`
plus the canvas's view state (view mode, projection, field of view, scene, variant, floor,
centring, selection). It is sent **whole** on every change; the page keeps the last one and only
redoes the expensive parts when they changed: a new environment is prefiltered (IBL), centring
or scene refits, projection restates the orthographic size. Before the first model, `apply` only
records the HDR; `open` starts it after the model so first paint does not wait on IBL, and
`still` waits for it so a thumbnail is lit.

`PageLook` (`RendererWebKit/WebRendererLook.swift`) is the one mapping to page values:

| `RenderLook` | Page | Source |
| --- | --- | --- |
| yaw Y (degrees) | `environmentRotation` = 90 + Y — yaw 0 is the Khronos default view | measured |
| exposure EV | `exposure` = 2^EV | measured |
| environment intensity E | `iblIntensity` = E | measured (1:1) |
| tone mapping | `toneMap` (raw value = Khronos name) | by definition |
| background | page background behind a transparent canvas | by definition |

Settings live in the App Group (`GLTFCore/AppGroupSettings.swift`). `Look.stored()` builds the
look from `AppGroupSettings.rendererLook()` (environment and tone map from the suite) for Quick Look and the thumbnail, so both light a file the same way; the pixel-diff
goldens use yaw 0 as well (manifest rotation 90).

There is no renderer setting. Window, Quick Look and the Finder thumbnail are this page.

---

## What changes the picture

The page never moves the model's geometry, materials or transforms. Everything below is camera, lighting, or line overlays drawn after the Khronos frame (`viewer.html` `drawOverlays`).

| Control | What it does | Window | Quick Look | Thumbnail |
| --- | --- | --- | --- | --- |
| Center | Aims the camera at the scene bounds. Off keeps the authored origin in frame and draws an origin gizmo. | on (`settings.preview.center`) | on | on |
| Fit | Projected-AABB fit, near-face depth, 1.02 padding, front view. Runs on open, scene switch, centre toggle, and Fit/Reset. | on open | on open | on open |
| Camera presets | Front / back / left / right / top / bottom at that fit distance. | — | — | — |
| File camera | Outliner camera row → `cameraNodeIndex`. The page views through that node's camera. | none | none | none |
| Field of view | User camera `yfov`. | 35° | 45° | 45° |
| Projection | Orthographic size from the camera distance, restated after every fit. | perspective | perspective | perspective |
| Auto-rotate | Orbits the camera. The model does not turn. | on | off | off |
| Floor | Grey polar grid of lines under the model. No shadow or reflection. | on | on | off |
| Background | Page background behind a transparent canvas. The HDR is not shown as a backdrop. | window | clear | clear |
| Environment | Bundled Khronos HDR. The first frame is key+fill; the IBL lands a frame or two later. | Studio Neutral | stored setting | stored setting |
| Environment rotation | `environmentRotation` = 90 + yaw. Yaw 0 is the Khronos default view. | 0 | 0 | 0 |
| Exposure / intensity | `exposure` = 2^EV, `iblIntensity` 1:1. | 0 EV / 1 | 0 / 1 | 0 / 1 |
| Tone mapping | Khronos `toneMap` by name. | PBR Neutral | stored | stored |
| File lights | `KHR_lights_punctual` drawn as authored, alongside the IBL. No toggle. | always | always | always |
| View mode | Shaded, wireframe, or a Khronos debug channel. Only channels the file has data for. | shaded | shaded | shaded |
| Selection | Blue AABB around the selected node's subtree. | none | — | — |
| Material variant | `KHR_materials_variants` index. Nil is the file default. | file default | file default | file default |
| Scene | Which glTF scene draws. 0 is the file's default scene. | file default | file default | file default |
| Pointer | Drag orbits, shift/middle-drag pans, scroll dollies with no clamp. | live | live | — |
| Animations, morphs, skins | The page draws the bind/rest pose. Nothing plays or poses. The inspector still lists them. | — | — | — |

The window field of view is `RenderCamera.defaultFieldOfViewDegrees` (35°). Quick Look and the thumbnail use `Look()`'s 45°.

Page `warning` events are logged (`WebRendererHost`) and are not shown in the inspector.

---

## Failure

- **Per-call timeout.** Every call (and the page start) has its own timeout
  (`WebRendererHost.timeout`, 15 s). A slow call fails alone; it never fails another one.
- **Dead page.** A WebContent crash (`webViewWebContentProcessDidTerminate`), a lost WebGL
  context (`webglcontextlost`) or an error outside any call fails every pending call and marks
  the host `isBroken`. The next `start()` loads a fresh page (a new WebContent process) instead
  of rethrowing the old error.
- **Canvas.** `WebCanvasController.phase` ends in `.failed(message)` when the page cannot start,
  rejects the file or times out before first paint (log: `viewport failed`, with the raw error).
  A page that dies after first paint is restarted once per model (log: `viewport restart`); a
  second death ends in `.failed`. The person sees `WebRendererError.userMessage` — friendly
  text, never the raw JS message. After first paint a failing look call is logged only.
- **Thumbnail.** A broken host, or one whose call timed out, is dropped so the next file gets a
  fresh page; the error goes back to Quick Look, which shows the generic icon.

---

## Window

`DocumentWindow` draws `WebPreviewCanvas` as soon as the file is opening; the canvas
region's state (`WindowLayout(canvasState:)`) follows the page, not the JSON panels. The
window holds one `WebCanvasController` across the shell's `.id(window.loadGeneration)` remount; the next
mount adopts the running `WKWebView` (log: `viewport adopt`).

**Commands.** `FocusedPreviewCommands` (fit / preset / reset / screenshot → `CGImage`) is
registered by the mounted canvas; `EngineViewportController` forwards the View menu, Camera
pill and Export PNG to it. Fit is `camera(.fit)`; a preset is `camera(.fit)` then
`camera(.orbit)` with the preset's angles and a distance scaled from the page's fit by the
preset's visible extent; the screenshot is `still` at the live canvas size. The host owns the
save panel.

---

## Stills and the thumbnail reply

`renderStillPNG(size:)` returns the page's PNG bytes; the thumbnail writes them straight to the
reply file (no decode and re-encode). WebKit's encoder tags the PNG `sRGB` (asserted in
`WebRendererHostTests`). `renderStill` decodes the same bytes where pixels are needed (window
screenshot, pixel diff). The WebGL context keeps its drawing buffer only in still mode;
`still()` renders and reads back in one task.

Finder consumes `QLThumbnailReply(imageFileURL:)`. The CGContext drawing reply fails in Finder
with `QLThumbnailError 102`. Thumbnail and preview targets need
`com.apple.security.network.client` so WebKit can spawn its Networking XPC, even though the
page makes no network requests; without it WebContent dies and thumbnails fail with the same
`102`.

---

## Vendored bundle

`web-renderer/gltf-viewer.module.js` is an esbuild minify of the rollup build of
`KhronosGroup/glTF-Sample-Renderer` — not patched or forked. `web-renderer/VERSION` pins the
upstream commit (`863b981`, `main` at the 2026-08-24 build) and the sha256 of every vendored
file; `THIRD_PARTY_NOTICES.txt` keeps the licence banner the minify dropped, plus hdrpng, the
libs and Draco. `./scripts/vendor-web-renderer.sh` checks the files against `VERSION`
(`record` after an intentional update); its header has the rebuild recipe.

The bundle still contains PhysX glue and the `KHR_interactivity` engine. Stubbing them needs a
rebuild from source (`npm ci`), which this repo does not do; not measured.

---

## Measured and not adopted (2026-09-30, 3 runs each)

| Idea | Result | Verdict |
| --- | --- | --- |
| One shared `WKWebsiteDataStore.nonPersistent()` per process | first page 220–232 ms vs 228–260 ms per-host; later pages 70–86 vs 71–96 ms | no win beyond noise |
| Spare warm host in the app | would save a warm page start (~75 ms) for a second window; the first window starts its page with the app anyway | not worth an idle WebContent |
| Off-main / memory-mapped model reads (256 MB GLB, warm cache) | open 129–230 ms either way; worst main-thread gap 33–38 ms (read), 32–41 (mapped), 18–34 (off-main) | no clear win; `didReceive` still copies on main |

### First-paint experiments (EXP-001…016, 2026-09-30)

Gate (bench-only timings, no longer logged): fresh-process `visibleMs` (page + IBL + load) or `stillMs` (first GPU frame + PNG) on
BoomBox and Corset, KEEP at ≥ 12 % faster with tiny not > 15 % slower. The wait is the page start,
not model parse: session-first ~1850 ms visible (page ~1170, IBL ~660), process-cold with WebKit
warm ~300–530 ms. Landed: IBL after the first frame (EXP-002, `iblMs` → 0), our module minified
6.1 → 3.2 MB (EXP-010), App Group poster under the live canvas (EXP-008; it replaced the cached Finder icon), Quick Look page
prestart in `loadView` (EXP-009).

**Measured slower or flat — do not retry without a materially different approach:**

| Idea | Result |
| --- | --- |
| Peek the GLB/JSON before `loadGltf` to defer KTX/Draco (EXP-001) | peek cost ate the page save on Corset / tiny |
| Stub KTX/Draco, inject on decode miss (EXP-005) | −5 / −10 %, under the gate; not banned |
| Stream the bundle through `WKURLSchemeTask` in 64 KB chunks (EXP-004) | +10 / +13 %; one read is faster |
| `WKWebsiteDataStore.default()` for a compile cache (EXP-006) | first-process page slower |
| Official npm `@khronosgroup/gltf-viewer` 1.1.0 module (EXP-007) | older build, `stillMs` ~2×; minify ours instead |
| Shared live host for Quick Look remounts (EXP-003) | first spacebar unchanged; only a possible second-open win |
| `internalMSAA = 0`, `floatingPointFramebuffer = false`, `maxAnisotropy = 1`, skip first-bind `generateMipmap` (EXP-011…014) | flat or slower `stillMs` |
| Skip the unused first-init FBOs or the still-mode tonemap blit (EXP-015/016) | `stillMs` worse, up to ~2× |

---

## Traps worth not rediscovering

- **Sandboxed settings.** `UserDefaults(suiteName:)` in an extension reads its own container,
  so `defaults write` on a shared suite never arrives — hence App Group settings written by the
  host only. `homeDirectoryForCurrentUser` / `NSHomeDirectory()` return the *container* home;
  `getpwuid(getuid())->pw_dir` gives the real one.
- **Assertions that pass on a wrong image.** "More than N distinct colours" passes on a
  near-black silhouette. Look at the PNG.
- **Skipped means not tested.** `TestModels/Khronos samples/` is gitignored, and
  `FileManager.enumerator` does not descend a symlinked root — which is why missing samples
  fail the pixel-diff run instead of skipping.
- **Stale registered app copies.** `lsregister -dump` can list the app from many locations, and
  `pluginkit` may resolve the thumbnail extension to an old DerivedData build. Check which copy
  is active before trusting a Finder thumbnail.
- **`qlmanage` is not Finder.** It hangs headless here, and `qlmanage -x` uses a different
  reply path. Verify through `QLThumbnailGenerator.generateBestRepresentation`.

---

## What this path does not do

- It does not share one in-memory glTF parse between Swift and the page — the window's panels
  read the JSON and the page loads the file itself.
