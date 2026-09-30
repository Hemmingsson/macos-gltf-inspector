# WebKit renderer: simplify for RendererWebKit

**Date:** 2026-09-30 · **Scope:** research only (no code changed) · **Worktree read:**
`.worktrees/webkit-renderer` @ `fa7dd64` + uncommitted tree · **Upstream read:**
`KhronosGroup/glTF-Sample-Renderer` @ `cc27919` (2026-09-22), `google/model-viewer` master.
**Feeds:** `.agents/plans/2026-09-30-renderer-separation.md` seams 5–6.

## Answer

Keep the Khronos glTF Sample Renderer and keep the one thin custom page. The page already
drives `GltfView`/`GltfState` directly with no Sample Viewer UI code, which is what upstream
intends. The complexity is in three places, and each has a smaller standard replacement:

1. **The bridge.** 23 commands, 23 Swift factories, an id/continuation table, a
   `postMessage` reply channel and per-command timers. `callAsyncJavaScript` removes most of
   it: it awaits the page's Promise, passes arguments as a dictionary and throws JS
   exceptions as Swift errors. With it, the page exposes about 5 functions and the look goes
   over as **one value object**.
2. **The bundle.** It is built by hand and has no script. It statically includes PhysX
   (`physx-js-webidl.mjs` is 4.7 MB unminified) and the `KHR_interactivity` engine, neither of
   which an inspector uses. A pinned, scripted esbuild build that stubs both is the largest
   untried `pageMs` lever. It also fixes a licence problem: the minified file has dropped every
   third-party notice.
3. **Failure handling.** Errors are only logged. The canvas keeps its spinner forever. A
   crashed WebContent process poisons the cached thumbnail host. Replace this with one state
   enum that ends in `.failed(message)`, and a host that knows it is dead.

Moving to three.js, model-viewer, Babylon or WebGPU would lower spec fidelity and would not
make the code simpler.

---

## 1. Current complexity map

### Files and size

| Piece | LOC / size | Notes |
| --- | --- | --- |
| `Shared/WebRenderer/WebRendererBridge.swift` | 472 | 23-case `Kind`, 23 static factories, a flat optional-field struct, `CameraPose`, `RendererCameraState`, `WebRendererEvent` (hand parse of 17 fields), 13-case error enum |
| `Shared/WebRenderer/WebRendererHost.swift` | 386 | WKWebView owner, id → continuation map, ready continuation, deferred-IBL state machine (4 vars + task), timeouts, message + navigation delegates |
| `Shared/WebRenderer/WebPreviewCanvas.swift` | 367 | NSViewRepresentable, 18-field `Look`, a 16-branch diff chain that sends one command per field (`:210-258`), loading chrome, placeholder, JSON peek task |
| `Shared/WebRenderer/WebRendererResourceHandler.swift` | 153 | 3 roots (renderer, environments, model and sidecars), synchronous `Data(contentsOf:)` |
| `Shared/WebRenderer/WebRendererLoadCopy.swift` | 88 | "Loading 12 textures…" copy from a JSON peek |
| `Shared/WebRenderer/CachedQuickLookThumbnail.swift` | 80 | Icon Services pixel-compare heuristic (EXP-008 KEEP) |
| `Shared/WebRenderer/RendererLookDefaults.swift` | 62 | reads the app's prefs plist through `getpwuid` (plan seam 2 replaces it) |
| `GLTFInspector/Engine/EngineLookBridge.swift` | 69 | maps `ViewportController` to `Look`, with Khronos string names |
| `Vendor/web-renderer/viewer.html` | 725 lines (~28 KB) | about 45% is a custom GL overlay: floor, origin gizmo, wireframe, selection AABB (`:147-384`) |
| Tests | ~1,780 | Controls 373, Host 218, LoadCopy 72, PixelDiff ~833, timing bench 217 |
| **Swift total** | **1,608** (+ ~70 host) | |

### JS bundle (`Vendor/web-renderer`, 6.2 MB in the working tree)

- `gltf-viewer.module.js` is **3.2 MB**. It is an esbuild minify (EXP-010) of a rollup build of
  upstream `main` from 2026-08-24, with header version 1.1.0 (`git show
  HEAD:Vendor/web-renderer/gltf-viewer.module.js | head`). It is **not patched or forked**: the
  source is upstream as-is. The minify is the only change.
- **Nothing reproduces it.** No `scripts/vendor-web-renderer.sh` exists, and the upstream SHA is
  not recorded. Compare `scripts/vendor-khronos-environments.sh`, which does exist for the HDRs.
- It statically bundles `physx-js-webidl` 2.7.2 (402 `physx` hits in the minified file; upstream
  `source/PhysicsEngines/PhysX.js:1` is a static import, and the `.mjs` alone is 4,772,538 B on
  unpkg). It also bundles `@khronosgroup/gltf-interactivity-engine`
  (`source/gltf/interactivity.js:2`), plus jpeg-js, fast-png, pako, meshoptimizer and gl-matrix.
  Physics only runs through `physicsController.initializeEngine()`
  (`source/GltfState/physics_controller.js:87`), which the page never calls. `physx-js-webidl.wasm`
  is correctly not shipped.
- **Licence finding:** `grep -c "Copyright\|@license"` on the minified module returns **0**. The
  pre-minify header listed MIT and BSD dependencies (gl-matrix, physx-js-webidl, jpeg-js, pako,
  fast-png, json-ptr, meshoptimizer), and those licences require the notice to be kept.
  `LICENSE.md` covers Khronos Apache-2.0 only.
- `libs/` is 2.2 MB: `libktx.{js,wasm}` 1.9 MB, Draco 250 KB, mikktspace 50 KB, splat sorter
  10 KB. `assets/` has 808 KB of LUT PNGs. The HDRs (`assets/ibl/khronos`, 4.4 MB) are served
  from a separate root.
- The same 6.2 MB plus 4.4 MB is copied into the app and both appexes (`project.yml:97,197,262`).

### Bridge commands (`viewer.html:429-700`)

`configure, setEnvironment, load, setScene, setCamera, setCameraPose, getCamera, fit,
setToneMapping, setExposure, setEnvironmentRotation, setDebugChannel, renderStill,
setBackdrop, setAutoRotate, setProjection, setFieldOfView, setFileCamera, setMaterialVariant,
setFloor, setCenter, setWireframe, setSelectedNode`

17 of the 23 are one-line property setters on `state.renderingParameters` or on page flags.
Transport works like this:

1. Swift builds the call as a string, `void window.__viewer.exec(<json>)`
   (`WebRendererBridge.swift:233-239`). The `void` avoids WKError 5 on a returned Promise.
2. The page replies with `postMessage({event:"result"|"failed", id, ...})`.
3. Swift matches the reply by `id` against `pending` (`WebRendererHost.swift:118-134, 313-353`).
4. The `progress` events the page sends are ignored (`:341-344`).

### Look

`WebPreviewCanvas.Look` has 18 fields (`WebPreviewCanvas.swift:45-75`) and is diffed field by
field in Swift. Each changed field is sent as its own awaited round trip. `sceneIndex` must
come after `load` (`:274-278`).

- Thumbnail builds its look separately: env and tone map only (`ThumbnailProvider.swift:84-96`).
- Quick Look uses `Look(environment:toneMapping:)` with every other field at its default
  (`PreviewViewController.swift:84-87`).

### Still pipeline

`ThumbnailProvider` runs a serialized chain through one cached `.still` host. For each file:

1. `load`
2. `renderStill`, which first joins the deferred IBL task
3. The page calls `renderFrame` and returns `canvas.toDataURL("image/png")` as a base64 string
4. Swift decodes it to a `CGImage` with `NSBitmapImageRep`
5. `StillRenderer.writePNG` re-encodes it to a temp file
6. `QLThumbnailReply(imageFileURL:)`

So the PNG is encoded twice, and it is always square, whatever
`request.maximumSize` says.

### Warm-up

| Surface | What it does |
| --- | --- |
| Quick Look | Prestarts a live host in `loadView` (EXP-009) and shows the cached Finder icon (EXP-008) |
| Thumbnail | One warm host per extension process |
| Window | New host per canvas mount. `start` runs in parallel with convert |

Each host creates its own `WKWebsiteDataStore.nonPersistent()` (`WebRendererHost.swift:72`).
IBL is deferred until after the first `load` (EXP-002).

### Error handling: what actually happens

- **Canvas:** errors are only logged (`WebPreviewCanvas.swift:155-157, 281-285`). The loading
  chrome stays visible, so Quick Look, which has no convert and so no `.failed` state, shows a
  **spinner forever**. `PreviewView` only shows a failure when *RealityKit convert* fails.
- **`start()` poisoning:** after a failure, `startTask` stays set and every later `start()`
  rethrows the same error (`WebRendererHost.swift:87-102`).
- **Thumbnail host after a crash:** `failAll` never clears `isReady`, and `ThumbnailProvider`
  keeps the cached host (`:85-88`). After a WebContent crash (for example jetsam on a huge
  file), every later thumbnail in that process is sent to a dead page and waits out the 15 s
  timeout. *(Inferred from code; not reproduced.)*
- **Timeout race:** `armTimeout()` starts a new, uncancelled 15 s task per command
  (`:282-290`). When any of those fires while *any* command is pending, it fails **all** of
  them. A command sent at t=14.9 s is killed by the timer armed at t=0. A load that takes more
  than 15 s always fails.
- **No context-loss handling:** there are no `webglcontextlost`/`restored` listeners.
- **Loader problems go to the console:** Khronos reports many load problems with
  `console.error` instead of throwing (21 call sites in `loader.js` and `gltf/*.js`; for example
  `resource_loader.js` "Only .glb files can be loaded from an array buffer"). The inspector
  never sees them.

### Correctness finding (look parity)

Khronos defaults `environmentRotation` to **90°** (`source/GltfState/gltf_state.js:137`; +Z
front). The window and Quick Look canvases always send `setEnvironmentRotation(0)` on first
apply, because `previous` is nil and `Look.environmentRotation = 0`
(`WebPreviewCanvas.swift:53, 219-223`). The thumbnail host never sends it, so it stays at 90.

**The Finder thumbnail and the Quick Look/window IBL are therefore rotated 90° from each
other.** That breaks the one-look rule. *(Inferred from code; confirm visually with
`Colorful_Studio`, which is asymmetric.)* The one-value look below makes this class of bug
structurally impossible.

---

## 2. External references (verified)

### Khronos glTF-Sample-Renderer (`@khronosgroup/gltf-viewer`)

- **Intended embedding** (`source/GltfView/gltf_view.js:9-100`):
  - `new GltfView(webgl2Context)` → `view.createState()` →
    `view.createResourceLoader(externalDraco?, externalKtx?, libPath?)`.
  - Then `state.gltf = await loader.loadGltf(url | ArrayBuffer | [name, File], externalFiles?)`,
    `state.environment = await loader.loadEnvironment(hdr, luts)`, and
    `view.renderFrame(state, w, h)` from your own rAF loop.
  - That is exactly what `viewer.html` does. The Sample *Viewer* (the separate
    `glTF-Sample-Viewer` repo) is a UI shell over this same API.
- **`createResourceLoader` does eager work:**
  - `initKtxLib` constructs `KtxDecoder`, which compiles `libktx.wasm` (1.7 MB) right away.
    Its source file is `ktx.js:10-15`.
  - `initDracoLib` is async but not awaited (`resource_loader.js:146-160`).
  - The `externalDracoLib`/`externalKtxLib` arguments are the supported way to pass these
    modules in, so the globals trick is not required. EXP-005 (stubs) went in the right
    direction but gained less than 12%.
  - `loadGltf` calls `init(mikktspace_bg.wasm)` on every load; it is cached after the first.
- **IBL cost** (`source/ibl_sampler.js:11-35`): 256² cube faces, 1024 GGX samples, 2048
  Lambertian samples, 64 sheen samples, RGBA16F preferred. All filtering runs on the GPU on
  every `loadEnvironment`. That is the ~50–70 ms warm / ~660 ms session-first `iblMs`. There is
  no public switch to lower it or to cache it. Keep EXP-002 (IBL after first paint), and cache
  `state.environment` per HDR name inside a page so switching back is free.
- **Rendering parameters** (`gltf_state.js:66-144`):
  - `toneMap` (default `KHR_PBR_NEUTRAL`), `exposure`, `environmentRotation` (90),
    `useIBL`, `iblIntensity`, `usePunctual`, `renderEnvironmentMap`, `blurEnvironmentMap`,
    `debugOutput`, `clearColor`, `internalMSAA: 4`, `floatingPointFramebuffer: true`
    (RGBA16F main buffer), `useDirectionalLightsWithDisabledIBL`.
  - `enabledExtensions` defaults `KHR_interactivity`, `KHR_node_visibility`,
    `KHR_gaussian_splatting` and others to true.
- **Animation API:** `state.animationIndices = [...]`, `state.animationTimer.start()`,
  `pause()`, `unpause()`, `reset()` and `setFixedTime(sec)` (`animation_timer.js`).
  `renderFrame` calls `_animate(state)`. `setFixedTime` is what a deterministic still of an
  animated file needs.
- **`KHR_node_visibility`:** supported natively. Visibility is an animatable property, so it
  also works with `KHR_animation_pointer`. Hide/solo should toggle node visibility in the page,
  not in RealityKit.
- **Picking is built in:** `state.selectionCallback`, `triggerSelection`,
  `selectionPositions`, `hoverCallback`, `enableHover` (`gltf_state.js:39-58`). Click-to-select
  in the viewport should use this instead of custom ray code.
- **WebGL2 only**, no WebGPU. Shader compile checks `COMPILE_STATUS`/`LINK_STATUS`
  synchronously (`Renderer/webgl.js:207,248`). That is the 117–465 ms first-frame cost; do not
  fork it.
- **npm is stale:** 1.1.0 is dated 2024-10. Vendor from git, as the decision doc says.
  EXP-007 confirmed the npm build is slower.

### Google `<model-viewer>`

- **Tone mapping:** the default is `'auto'`, which maps to three.js `NeutralToneMapping`
  (`features/environment.ts:63,101-102`; `three-components/Renderer.ts:161`). That is the same
  Khronos PBR Neutral this app defaults to, so the default is well supported.
- **Stills:** `toBlob({mimeType, qualityArgument, idealAspect})`
  (`model-viewer-base.ts:508-555`). It renders, `drawImage`s the WebGL canvas into a 2D canvas
  in the same task, then uses async `canvas.toBlob`. So it needs no `preserveDrawingBuffer`,
  and it crops to the model's ideal aspect.
- **Fidelity CI:** `render-fidelity-tools` runs Puppeteer goldens with an RMS-in-dB threshold
  of −22 dB (`src/common.ts:29-31`). Scenarios are Khronos sample assets
  (`test/config.json`), the same idea as this repo's `PixelDiffTests`.
- **Not a fit here:** it is a web component with AR, poster, shadow DOM and its own framing on
  top of three.js. It would add policy, not remove it.

### three.js and Babylon.js

- **three.js `GLTFLoader`** (docs, fetched): variants, `KHR_animation_pointer` and gaussian
  splatting need plugins. `KHR_materials_pbrSpecularGlossiness`,
  `KHR_materials_diffuse_transmission` and `KHR_node_visibility` are not listed. Its parse was
  5–10× slower than Khronos in the 2026-08-24 measurement (`docs/decision-web-renderer.md`).
  `WebGPURenderer` exists, but it buys no fidelity for inspection.
- **Babylon.js** has broad extension coverage but is a large engine and is not the reference.
  *(Not re-measured here.)*

### WKWebView on macOS 26

- **`callAsyncJavaScript(_:arguments:in:contentWorld:)`** (macOS 11+; async Swift overload
  returns `Any?`):
  - It awaits a returned Promise.
  - Arguments are passed as a dictionary, with no string-built JSON.
  - A JS throw becomes a Swift error.
  - Allowed result types are NSNumber, NSString, NSDate, NSArray, NSDictionary and NSNull.
    **There is no binary type**, so PNG bytes still cross as a base64 string.
  - `WKScriptMessageHandlerWithReply` is the reverse direction (JS awaits Swift). This app
    does not need it.
  - Sources: [Apple, callAsyncJavaScript](https://developer.apple.com/documentation/webkit/wkwebview/callasyncjavascript(_:arguments:in:in:completionhandler:)),
    [WKWebView.h](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKWebView.h).
- **Process pool:** `WKProcessPool` has been a no-op since macOS 12. Processes are shared **by
  `WKWebsiteDataStore`**, so creating a new `.nonPersistent()` store per host prevents sharing
  ([Apple WKProcessPool](https://developer.apple.com/documentation/webkit/wkprocesspool),
  [WKProcessPool.h](https://github.com/WebKit/webkit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKProcessPool.h)).
  EXP-006 showed `.default()` is worse. **One shared `.nonPersistent()` instance per process**
  is a different hypothesis and has not been tested.
- **`takeSnapshot`** does not reliably capture WebGL, and WebKit does not render views that are
  offscreen or not in a window
  ([forum 82368](https://developer.apple.com/forums/thread/82368),
  [forum 710015](https://developer.apple.com/forums/thread/710015)). Keep canvas readback for
  stills.
- **`WKURLSchemeHandler`:** calling `didReceive`/`didFinish` on a task that WebKit already
  stopped raises an ObjC exception
  ([Apple forum 712430](https://developer.apple.com/forums/thread/712430),
  [wry #1822](https://github.com/tauri-apps/wry/issues/1822)). If reads move off the main
  thread, track stopped tasks. EXP-004 showed that 64 KB chunking is slower, so keep one
  `didReceive`.
- **WebGPU** is enabled by default in Safari and WebKit 26 on macOS
  ([WebKit, Safari 26.0](https://webkit.org/blog/17333/webkit-features-in-safari-26-0/)).
  It is irrelevant while Khronos is WebGL2-only.
- **WebGL:** compile then link then query status to allow parallel compile; avoid sync `get*`
  calls; readback is synchronous
  ([MDN WebGL best practices](https://developer.mozilla.org/en-US/docs/Web/API/WebGL_API/WebGL_best_practices)).
- **`preserveDrawingBuffer: true`** forces WebKit to keep, and on tile GPUs copy, the back
  buffer every frame. It is only needed when reading pixels *in a later task*. `renderStill`
  already renders and reads in one task. *(General WebGL guidance; the cost on Apple Silicon
  was not measured here.)*
- **Colour:** Khronos tone-maps and sRGB-encodes into the default framebuffer, with RGBA16F
  internally. Keep the canvas `drawingBufferColorSpace = "srgb"` (the default). WebKit colour
  manages it to the P3 display. Switching the canvas to `display-p3` or a float16 drawing
  buffer would reinterpret sRGB values and **break reference parity**. Verify that the PNG from
  `toDataURL` carries an sRGB profile, which ImageIO would read.

---

## 3. Alternatives

| Option | Spec fidelity | Size / perf | Complexity | Verdict |
| --- | --- | --- | --- | --- |
| **Khronos renderer + thin custom page (today)** | Reference implementation. Spec-gloss, variants, `animation_pointer`, `node_visibility`, 13+ debug channels | 3.2 MB module; parse 11–23 ms; first-frame shader compile is the cost | Low, once the bridge is fixed | **Keep** |
| Khronos, stripped build (no PhysX or interactivity) | Same, minus physics and interactivity, which an inspector does not use | Likely well under half of 3.2 MB *(measure)* | +1 script | **Do** |
| model-viewer | three.js-level: loses spec-gloss, diffuse transmission, `node_visibility` | Smaller JS; its own framing and tone mapping | Adds a component with policy you would work around | No |
| three.js direct | Same gaps; plugins for variants and pointer | 5–10× slower parse (measured) | Loader glue plus a PMREM trap (see decision doc) | No |
| Babylon | Broad, but not the reference | Heavy | Large API | No |
| WebGPU renderer | No Khronos WebGPU backend | n/a | New stack | Not now |

---

## 4. Target architecture for `RendererWebKit` (minimal)

### Page: one HTML page, two ES modules

```
web/
  renderer.html     # <canvas>, classic libktx + draco scripts, <script type=module src=page.js>
  page.js           # ~250 lines: boot, 5 API functions, pointer controls, rAF loop
  overlays.js       # floor / origin gizmo / wireframe / selection AABB (moved from viewer.html)
  gltf-viewer.module.js, libs/, assets/, environments/*.hdr   # one root, one scheme
```

- **Mode and size go in the URL:** `renderer.html?mode=still&size=512`. That removes
  `configure`. It also lets the context be created with
  `preserveDrawingBuffer: false` in live mode, which cannot be done after
  `getContext`.
- **API.** Every function is async and returns plain JSON:

  | Function | What it does |
  | --- | --- |
  | `open({url})` | Returns `{sceneCount, animationCount, triangles, meshes, parseMs, warnings[]}`. `warnings` is what `console.error` captured during the load |
  | `apply(look)` | Takes the **whole** look; the page diffs it. Only an environment change awaits the IBL, and the prefiltered `state.environment` is cached per HDR name. It also takes playback (`animationIndices`, play/pause, fixed time) and `hiddenNodes` (`KHR_node_visibility`) when those land |
  | `camera({op: "fit" \| "orbit" \| "pose" \| "get", ...})` | The four camera operations |
  | `still({size?, pose?, time?})` | Awaits pending IBL, renders, returns the base64 PNG. Optionally uses the `idealAspect` crop the way model-viewer does |
  | `stats()` | Optional |

- **Push events** (`postMessage`, no ids): `error`, `contextlost`, `contextrestored`.

### Swift: about 5 types instead of 7 files and ~1,600 lines

- **`WebRendererHost`** (~150 lines):
  - Owns one `WKWebView`, using a **process-wide shared** `WKWebsiteDataStore.nonPersistent()`
    *(measure)*.
  - One generic call:
    `func call<R: Decodable>(_ fn: String, _ arg: some Encodable) async throws -> R`. It
    encodes with `JSONEncoder`, converts to a dictionary, calls
    `callAsyncJavaScript("return await __viewer[fn](arg)", arguments: ["fn": fn, "arg": dict], contentWorld: .page)`,
    and decodes the result.
  - Timeouts are per call (a `withTimeout` wrapper), never a global `failAll`.
  - `webViewWebContentProcessDidTerminate` sets the host to `state = .dead(error)`. Owners
    drop a dead host, and the thumbnail cache recreates it.
- **`RendererLook: Codable, Equatable`** is the single look value, taken from PreviewUI types
  (plan seam 4 decision). The thumbnail, Quick Look and the window all build it the same way,
  from App Group settings. That fixes the 90° finding.
- **`WebRendererCanvas`** (NSViewRepresentable) keeps a phase enum:
  `starting → loading → ready | failed(String)`. It reports the phase upward so
  `PreviewSession` shows `.failed(message)`. `updateNSView` just calls `apply(look)`, and
  cancel-and-replace a task per update is enough.
- **`WebRendererResourceHandler`** serves one bundle root plus `/model/*`:
  - Model reads run off the main thread with `Data(contentsOf:options:.mappedIfSafe)` and
    deliver on main, only if the task was not stopped *(measure on a 200 MB+ file)*.
  - Moving the HDRs into the renderer resources at build time removes the environment root.
- **`renderStill(url:size:look:) -> Data`**: return the PNG bytes and write them straight to
  the thumbnail file, with no CGImage decode and PNG re-encode. Decode to `CGImage` only where
  a caller needs one, such as the pixel diff.

### Warm-up

| Surface | Strategy |
| --- | --- |
| Quick Look | Keep EXP-009 (prestart in `loadView`) and EXP-008 (cached icon) |
| Window | A process-wide "one spare started host" pool. Take on mount, refill when idle. This targets the session-first `pageMs` of ~1,170 ms vs ~200 ms warm. *(Measure with `webkit-first-paint-bench.sh`.)* |
| Thumbnail | Keep the warm host. Recycle it on death, and after N renders or an RSS threshold. *(Measure folder-scale; the decision doc lists this as the open bill.)* |

### Bundle: built once, shipped once

- Add `scripts/vendor-web-renderer.sh`. It clones at a pinned SHA and runs `npm ci`. It then
  runs esbuild with:
  - `--alias:physx-js-webidl=./stubs/physx.js`
  - interactivity stubbed as well, with `enabledExtensions.KHR_interactivity=false` set in the
    page
  - `--minify --legal-comments=external`
- It writes `VERSION` (SHA, date, sizes) and `THIRD_PARTY_NOTICES`.
- The output ships once in `RendererWebKit.framework/Resources`, pending the plan's seam 3
  spike.
- **Risk:** the interactivity import is namespace-wide (`import * as interactivity`), so a stub
  must export whatever `GraphController` touches at construction. Verify by loading the
  12-model pixel-diff set with no new console errors.

### What to delete

| Delete | Why |
| --- | --- |
| `WebRendererCommand` (23 cases and factories), `WebRendererEvent`, id/pending/ready/timeout machinery, the `void` exec hack, the `progress` event | Replaced by `callAsyncJavaScript` plus `Codable` |
| The 16-branch look diff in `WebPreviewCanvas` and the 17 per-field page commands | Replaced by one `apply(look)` |
| The `configure` command and the `start(size:)` re-configure path | Mode and size go in the URL |
| The separate environment root in the scheme handler | One root |
| `RendererLookDefaults` plist read | Already planned (seam 2) |
| `WebRendererLoadCopy` + `WebRendererAssetInventory` peek (160 LOC with tests), *optional* | Visible time is now ~200–500 ms. A plain spinner over the cached icon is honest enough, and it removes a second JSON parse on the open path. Product call |
| `setCamera` vs `setCameraPose` duplication | One `camera` op; keep `CameraPose` `Codable` for the goldens |

Keep: the overlays (moved to `overlays.js`), the pointer controls, `CachedQuickLookThumbnail`
and the pixel-diff harness.

---

## 5. Ranked recommendations

| # | Change | Value | Risk | Needs measurement? |
| --- | --- | --- | --- | --- |
| 1 | Failure states: phase enum, `.failed(message)`, dead-host detection, per-call timeout, `webglcontextlost` event, captured `console.error` warnings | High (spinner forever, poisoned thumbnail host) | Low | Only manual: corrupt `.glb`, `kill -9` WebContent |
| 2 | One `RendererLook` value and `apply(look)`; fixes the 90° env-rotation mismatch | High (one-look rule, and deletes ~300 Swift LOC) | Low | Visual check: thumbnail vs Quick Look on `Colorful_Studio` |
| 3 | `callAsyncJavaScript` bridge with about 5 functions | High (deletes ~500 LOC) | Low | Confirm `undefined`/`nil` returns and error message mapping in a unit test |
| 4 | Scripted vendor build: pinned SHA, PhysX and interactivity stubbed, legal comments kept | High (reproducibility, licence compliance, likely `pageMs`) | Medium (stub surface) | Yes: `pageMs` proc-cold and session-first, plus pixel-diff green |
| 5 | Stills return PNG bytes to a file (no decode and re-encode); `preserveDrawingBuffer` only in still mode | Medium | Low | Yes: `stillMs`, live frame time |
| 6 | Shared `nonPersistent` data store per process, plus a one-spare-host pool in the app | Medium to high for the first window | Medium (memory) | Yes: bench `cold` / session-first, RSS |
| 7 | Off-main, mapped model reads in the scheme handler; one resource root | Medium for big files | Low to medium (stopped-task exceptions) | Yes: a 200 MB+ file, main-thread hangs |
| 8 | Cache prefiltered `state.environment` per HDR in the page | Low to medium (look toggles) | Low | Quick check |
| 9 | Use built-in picking (`selectionCallback`) and `KHR_node_visibility` for hide/solo when those features land | Removes future custom code | Low | n/a |

## Unresolved

- Whether the PhysX and interactivity stub is clean enough without patching upstream source
  (the aim is alias only, no fork).
- Real `pageMs` share of PhysX glue parse under JavaScriptCore lazy parsing. It may be smaller
  than the size suggests, since EXP-010's halving gained about 10%.
- Whether a shared `nonPersistent` store beats per-host stores in the appexes, where there is
  only one host anyway. It mostly matters in the app.
- Alpha: the page uses `alpha: true` with default `premultipliedAlpha`. Check transparent
  (`BLEND`) materials over the `.window` backdrop for halos against the Sample Viewer.
- Whether `toDataURL` PNGs carry an sRGB profile. If not, tag the file in Swift when writing
  it.
- `RendererTimingBenchTests.swift` is untracked on `main` too. Confirm it belongs to the
  `webkit-renderer` branch.
