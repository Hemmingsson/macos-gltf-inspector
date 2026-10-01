# Tidy pass: GLTFCore, RendererWebKit, WebKit host adapter, extensions

**Date:** 2026-10-01 · **Branch:** `next-main` @ `b29ad5b` (clean tree) · **Scope:** research only,
no code changed. **Read:** all of `GLTFCore/`, `RendererWebKit/*.swift` + `web-renderer/viewer.html`
(not the vendored module), `GLTFInspector/WebKit/`, `PreviewExtension/`, `ThumbnailExtension/`,
`GLTFInspectorTests/WebKit/` and the root tests that cover core. Each "dead" claim was checked with
grep over the whole repo, tests included.

**Already done; not proposed again:** the `callAsyncJavaScript` five-function bridge, the
one-value `Look`, the failure phase and dead-host handling, the vendor pin and notices, PNG bytes
straight to the thumbnail, still-only `preserveDrawingBuffer`, the `RendererLookDefaults` plist
read, and the `Shared/` split (see `git log main..HEAD`, 89 commits). Measured and rejected:
a shared data store, a spare warm host, off-main model reads (`docs/pipeline-web-renderer.md`
§Measured), and EXP-001…016. Kept on purpose: `CachedQuickLookThumbnail` (EXP-008 KEEP) and the
load copy (KEEP in `186e7d4`).

## Answer

There is no large rewrite left. The remaining complexity is duplication inside `GLTFCore`'s JSON
readers, public-init boilerplate, a few dead paths in the web canvas, and benchmark code that runs
in every `dev.sh test`. Nine independent chunks remove roughly **650–700 lines** (about −550 of
them Swift) and change no behaviour, apart from three small, flagged improvements in edge cases.

**Settings keys (the question asked):** there is no simpler single source under the current
module rules. PreviewUI must not import GLTFCore. GLTFCore must stay extension-safe, and PreviewUI
is not (`NSApp`). A source file shared between both targets would bring back the `Shared/`
pattern this branch removed. So keep `AppGroupSettingsTests`, but shrink what it guards: the core
should hold only the keys an extension or a renderer reads. `showToolbar` is used only in tests,
and `appearance` is read only by the host, which can use `SettingKey.appearance.name`. That leaves
5 keys, not 7 (chunk E).

## Ranked chunks

| # | Chunk | Value | Risk | Net LOC | Depends on |
| --- | --- | --- | --- | --- | --- |
| H | Gate the always-on WebKit benches, delete experiment leftovers | High (test time, machine-specific paths) | Low | ≈ −190 (incl. docs) | E (shares one test file; touch only the thumbnail section) |
| D | `GLTFSessionDocument`: delete the hand-written public memberwise inits | High per hour | Low (compiler-checked) | ≈ −165 | — |
| C1 | `PreviewStats`: reuse `GLTFBinaryStore` / `GLTFImageDecode`; one `from` | Medium–high | Low–medium (edge-case fix) | ≈ −60 | — |
| C2 | One internal JSON-value helper; `MaterialMapPresence` from the one binding table; dead `GLBBox` API | Medium | Low | ≈ −70 | after C1 (mechanical call sites in `PreviewStats.swift`) |
| F | Web canvas: drop the dead private-controller and in-canvas failure paths; split the file | Medium | Low–medium | ≈ −45 (split itself neutral) | — |
| E | Settings and look surface: 5 core keys, `RenderLook` straight from the store, dead `AppLook` API | Medium | Low | ≈ −40 | — |
| G | Host, bridge and page tidy; one `uptimeMs`; environments by name | Low–medium | Low | ≈ −40 | after F (rename in the controller file); touches `AppLook.swift` lines 18–23 after E |
| I | Small core dead code: validator badges, `#filePath` fallback, `RendererKind.store`, `AppLog.prepare` | Low | Low | ≈ −35 | — |
| J | RealityKit `unionModelBoxes` → `ModelBounds.union` | Low–medium | Low | ≈ −30 | — |
| K | Extension and adapter dedupe (thumbnail temp URL, QL failure view, window status views) | Low | Low | ≈ −25 | — |
| M | *(optional)* move `viewer.html` overlays to `overlays.js` | Readability only | Medium (page load order) | ≈ 0 | G |

Every chunk is verified with `./scripts/dev.sh test`. That runs the pixel-diff goldens for both
renderers, the validator corpus and the unit suites. Chunks F, G and M also need one real window
and one Quick Look open on a WebKit build (AGENTS.md pitfall 9).

---

## H — Benches that run in every test, and experiment leftovers

| Evidence | Why it is complexity | Change |
| --- | --- | --- |
| `GLTFInspectorTests/WebKit/RendererTimingBenchTests.swift:24` has no `.enabled(if:)`. It runs 5 assets × 2 cold repeats plus warm passes, with 180 s timeouts, on every `dev.sh test` | Slow tests, and a benchmark posing as a test | Gate it on the request the bench script already writes: `.enabled(if: env["WK_FP_MODE"] != nil \|\| FileManager.fileExists("/tmp/glb-preview-webkit-fp-bench/request"))`, the same pattern as `LookProbeGate` (`CrossRenderer/LookProbeTests.swift:31-36`) |
| `RendererTimingBenchTests.swift:87-88` hard-codes `/Users/mattias/dev/glb-preview/TestModels/Khronos samples` (the main checkout, not this worktree) and `~/Downloads`, with BoomBox and Corset marked `required: true` | Fails on any other machine or checkout; reads a different tree than the one under test | Use `TestModels.khronosDirectory` (`TestFixtures.swift:42`). Drop the two `Downloads` assets, or keep them optional |
| `WebRendererControlsTests.swift:338-383`: `recordsSingleFileStillTiming` (a spike comparison point) and `recordsFolderScaleStillTiming` (100 warm stills plus 12 cold hosts, **ungated**) | Spike benches left in the product suite. Their only assertions are `< 15 s` and `< 5 s/file` | Delete both. The bench script and `docs/webkit-first-paint-experiments.md` already own those numbers. Or move them behind the same bench gate |
| `scripts/seed-webkit-fp-exp.sh` (32 lines) exits unless run from `*/webkit-renderer`, a champion worktree that no longer exists; `docs/webkit-perf-experiment-loop.md` (80 lines) is built around it | Dead tooling and process doc | Delete both. Keep the ledger `docs/webkit-first-paint-experiments.md`, which has the EXP table and "Must not retry". Update the `docs/README.md` rows. That README's RealityKit row ("prepare → … not the canvas") is also stale: prepare was deleted and RealityKit is the default canvas |

**Risk:** low. The bench still runs through `webkit-first-paint-bench.sh`, which writes the request
file before it calls `xcodebuild`. **Verify:** `dev.sh test` gets faster, with no `wk-fp` or
`thumb-bench` lines in the log. `./scripts/webkit-first-paint-bench.sh --label check` still prints
`wk-fp` rows. **LOC:** about −60 test lines (or 0 if gated) and about −110 lines of docs and scripts.

## D — `GLTFSessionDocument` init boilerplate

`GLTFCore/GLTFSessionDocument.swift` (344 lines) writes out a public memberwise init for the
document and for every nested type: Scene, Node (39 lines, `:85-123`), Camera, Light, TextureSlot,
Material (29 lines, `:263-291`), Skin, Morph and Animation. Outside `GLTFCore` the only things
built are `GLTFSessionDocument()` (`DocumentWindowModel.swift:27,65`,
`RendererRealityKit/PreviewScene.swift:37,89`) and `MaterialMapPresence()`
(`RendererRealityKit/MaterialMapPresence+GLTFKit.swift:7`). Every test that builds nested values
uses `@testable import GLTFCore` (`SelectionDetailTests`, `HostSidebarModelTests`, …).

- **Change:** delete the nested inits and let Swift synthesize internal memberwise inits. The
  parameter order already matches declaration order, and every `var` has a default or is
  optional. Keep only `public init() {}` on `GLTFSessionDocument` (and on `MaterialMapPresence`;
  see C2).
- **Stale comments in the same file:** "Pixel size / thumb filled after convert" (`:198`),
  "thumbs stamped after convert" (`:260`), "Skin joint list stamped at convert" (`:294`) and
  "Names match RealityKit blend-shape offsets" (`:315`). All of these are now JSON-side
  (`GLTFDocumentJSON.stampTexturePreviews`).
- **Risk:** low. A missed public construction site fails to compile, it does not misbehave.
  **Verify:** build all targets, then `dev.sh test`. **LOC:** about −165.

## C1 — `PreviewStats` re-implements the binary store

`GLTFCore/PreviewStats.swift:131-191` resolves image bytes and sizes on its own: `glbBin`
re-reads and re-parses the whole GLB, `imageBytes` slices bufferViews, and `imageMaxEdge` reads
ImageIO headers. `GLTFBinaryStore.imageBytes` (`GLTFBinaryStore.swift:47`) and
`GLTFImageDecode.pixelSize` (`GLTFImageDecode.swift:10`) already do the same. Per summary, the GLB
is therefore read twice (`GLTFDocumentSummary.swift:30-38`: once for the document, once for the
stats).

- **Change:**
  - Implement `maxTextureEdge` as
    `images.compactMap { store.imageBytes($0).flatMap(GLTFImageDecode.pixelSize) }`.
  - Let `GLTFDocumentSummary` pass one store to both callers (add an internal
    `from(json:…, binary:)`).
  - Collapse the two public `from` overloads and the private `fromJSONCounts` (`:40-56,105`) into
    one `from(json:animationCount: = 0, fileSizeBytes: = nil, resourceURL: = nil)`.
  - Expose `compact(_:)` (`:273-289`) as `static func compactCount` and delete its verbatim copy in
    `RendererWebKit/WebRendererLoadCopy.swift:73-89`.
  - Fix the header comment, which says animation count comes from "converted usable clips"
    (`:4-5`): the WebKit path counts JSON clips (`GLTFDocumentSummary.swift:35`).
- **Behaviour delta (improvement, flag in the PR):** the store percent-decodes sidecar URIs,
  decodes non-base64 `data:` URIs, and resolves bufferViews in external `.bin` buffers. The old
  code handled none of these (`:172-178`, `:162-164`), so `maxTextureEdge` can now be non-nil on
  such `.gltf` files.
- **Risk:** low–medium. **Verify:** `PreviewStatsTests`, `SessionDocumentTests`,
  `WebRendererLoadCopyTests`. Add one test with a `.gltf` whose image is a bufferView into a
  sidecar `.bin`. **LOC:** about −60.

## C2 — One JSON-value helper; one texture-binding table

| Evidence | Change |
| --- | --- |
| The JSON scalar helpers live on `GLBBox`, a GLB chunk type (`GLBBox.swift:95-114`), and are copied around it: `intArray` ×2 (`GLTFDocumentJSON.swift:585`, `ModelBounds.swift:176`); `float3` ×2 with different tolerance (`GLTFDocumentJSON.swift:593`, `ViewModeAvailability.swift:138`); node matrix parsing ×2 (`GLTFDocumentJSON.swift:141-169` Float, `ModelBounds.swift:156-174` Double); `accessorCount` and triangles-by-mode ×2 (`GLTFDocumentJSON.swift:209-255`, `PreviewStats.swift:222-271`) | Add one internal `enum GLTFJSON` (`int`, `double`, `doubles`, `ints`, `float3`, `float4`, `accessorCount`, `primitiveCounts`) and point every reader at it. Nothing outside `GLTFCore` calls `GLBBox.intValue` / `doubleValue` / `doubleArray` (grep), so they go internal and move out |
| `MaterialMapPresence.from(json:)` (`MaterialMapPresence.swift:39-72`) duplicates `GLTFDocumentJSON.textureRefs` (`:391-423`, whose comment says "Mirrors `MaterialMapPresence.from(json:)`") | Build presence from `textureRefs(material).map(\.kind)`, so there is one binding table. Edge: a malformed non-object value such as `"normalTexture": 5` would stop counting as a map (`textureRefs` requires a dictionary). Delete the 21-line public memberwise init and keep `public init() {}` (tests are `@testable`) |
| Dead `GLBBox` API: `readUInt16` (`:116`, no callers), `Error.missingBuffer` (`:17`, never thrown), `aligned` is public but used only at `:63`, and `readUInt32` / `decodeDataURI` are core-only | Delete or make internal |
| Stale comments: `GLBBox.peekJSON` says "so prepares can bail" (`:68`; prepares were deleted); `GLTFDocumentJSON.minimumClipDuration` says "Twin of `AnimationSampling.minimumDuration`" (`:522`; no such symbol exists, RealityKit has `hasPositiveDuration`) | Fix the wording |
| `GLTFDocumentJSON.makeDocument(json:binary:)` is an internal overload whose only caller is the public one (`:12-16`) | Inline it, or keep it only if C1 needs the shared store |
| `GLTFDocumentJSON.swift` is 607 lines | Natural split: move Materials and texture previews (`:326-487`, about 160 lines) to `GLTFDocumentJSON+Materials.swift` |

**Risk:** low. **Verify:** `SceneModelFromJSONTests`, `SessionDocumentTests`,
`JSONModelBoundsTests`, `RealityKit/JSONModelBoundsRealityKitTests`, `PreviewDebugModeTests`
(it uses `ViewModeAvailability`), the validator corpus and `dev.sh test`. Optionally merge the
two document test files, whose names overlap, into `GLTFDocumentJSONTests`. **LOC:** about −70.

## F — Web canvas dead paths and file split

`RendererWebKit/WebPreviewCanvas.swift` (435 lines) holds three things: the SwiftUI loading view
(`:7-38`), the representable (`:45-95`) and `WebCanvasController` (`:104-420`).

| Evidence | Change |
| --- | --- |
| Every caller passes `controller:`: `WebDocumentWindow.swift:86-93`, `QuickLookWebKit.swift:115-117`, and the tests mount through `attach` directly. So `controller ?? WebCanvasController(outlivesMount: false)` (`:71`), `outlivesMount` (`:115,133`) and the whole `detach` body (`:225-241`) never run | Make `controller` non-optional and delete the private-controller path. `dismantleNSView` then does nothing and can go. Update the public-API line in AGENTS.md |
| Both owners swap the canvas out as soon as `phase == .failed` (`WebDocumentWindow.swift:82-84`, `QuickLookWebKit.swift:112-113`), so the in-canvas failure chrome (`fail` at `:357-363`, `showsSpinner` at `:11`, `WebRendererLoadCopy.failed`) is never on screen | Delete it. `fail` sets `phase` and logs. Keep the "never a spinner" guarantee in the owners, and keep `corruptFileEndsInFailedNotASpinner` |
| `reset()` is `fit()` (`:145-147`) | Point `FocusedPreviewCommands.web` reset at `canvas.fit()` (`GLTFInspector/WebKit/FocusedPreviewCommands+WebKit.swift:19`) and delete `reset()` |
| After `start`, the load copy is re-shown (`:280-285`) even though the detached peek task at `:267-276` already shows it | Delete the second block; keep `inventory = await peek.value` for the "Drawing…" detail |
| The header calls this the "First step of the viewport migration … Sidebar … still read the RealityKit document" (`:40-44`) | Stale. Rewrite it in one line |
| Split | `WebCanvasController.swift` (the controller). `WebCanvasLoading.swift` (the loading view, `WebRendererLoadCopy` and the asset inventory, so first-paint status lives in one place). `WebPreviewCanvas.swift` keeps the representable and `features` |

**Risk:** low–medium. The failure chrome is the "pitfall 2" safety net, and now the owners alone
provide it; both are covered by `WebCanvasRoutingTests` and the QL view switch. **Verify:**
`WebCanvasControllerTests`, `WebCanvasRoutingTests`, `dev.sh test`, then a real window and a Quick
Look of `TestFixtures.corrupt` on a WebKit build: a failure message, no spinner. **LOC:** about −45.

## E — Settings and look surface

| Evidence | Change |
| --- | --- |
| `AppGroupSettings.Key.showToolbar` is used only in tests (`EngineSettingsStoreTests.swift:140`, `AppGroupSettingsTests.swift:16`). `Key.appearance` is read only by the host (`GLTFInspectorApp.swift:18`), which imports PreviewUI | Drop both from core. The host uses `SettingKey<String>.appearance.name`, and the tests use the `SettingKey` names. `AppGroupSettingsTests.previewUIKeyNamesMatchTheGroupKeys` then guards the 5 keys extensions read |
| `rendererLook()` returns `(String, String)` (`AppGroupSettings.swift:71-81`), which `Look.stored` parses back into enums (`WebRendererLook.swift:64-67`): enum → string → enum | Return `RenderLook` (or add `RenderLook.stored(defaults:directory:)` in core). Delete `defaultEnvironment` (test-only) and `defaultToneMapping` (`:30-31`) in favour of `RenderLook.standard` |
| `rendererLook` logs `directory.path` on every call (`:79`), and it runs once per Finder thumbnail via `.stored()` (`ThumbnailWebKit.swift:36`) | Leftover verification logging. It also breaks AppLog's own rule against full paths (`AppLog.swift:5-7`). Delete it |
| `AppLook.current` (`AppLook.swift:85`) has no callers; `AppLook.supportDirectory()` (`:49`) is an alias of `AppGroupSettings.containerURL` | Delete `current` and inline the alias |
| The `RendererLookDefaultsTests` struct (`WebKit/WebRendererControlsTests.swift:227-288`) is named after a deleted type. Two of its tests exercise core only and repeat `AppGroupSettingsTests.hostWritesRoundTripThroughTheReader` | Move `fallsBackToTheReviewOrientedDefaults` and `everyToneMappingRoundTripsThroughItsStoredName` to root tests, delete `readsWhatTheAppStored`, and keep the render test under a truthful name |
| Stale comments: `SettingsStore.swift:21,31` ("registered in `GLTFInspectorApp.init`"); `AppGroupSettings.swift:33-34` says each extension calls `registerDefaults()`, but only `rendererLook` and the host do | Fix the wording |

**Risk:** low. **Verify:** `AppGroupSettingsTests`, `EngineSettingsStoreTests`,
`EngineAppDefaultsBridgeTests`, `WebRendererLookTests`, the WebKit pixel diff (thumbnail look).
**LOC:** about −40.

## G — Host, bridge and page tidy

| Evidence | Change |
| --- | --- |
| `LoadInfo.sceneCount` / `animationCount` (`WebRendererHost.swift:24-25`) are filled by the page (`viewer.html:569-570`) and read nowhere | Delete them on both sides. `parseMs` / `fitMs` stay while the bench uses them |
| `LoadInfo` and `Stats` are bridge values but live in the host (`:21-46`); `WebRendererBridge.swift` is documented as "Values that cross the page bridge" | Move them, along with the error enum's neighbours, into `WebRendererBridge.swift` |
| `RendererCameraState.pose` is an alias of `camera` (`WebRendererBridge.swift:69-73`) | Rename the page key to `pose` (`viewer.html:505`) and delete the alias |
| Two copies of `uptimeMs`: `GLTFInspector/DocumentWindowModel.swift:240` and `WebRendererHost.swift:88` | Keep one `AppLog.uptimeMs()` in core and update the callers in `DocumentWindowModel`, `RealityDocumentWindow.swift:196`, `WebRendererHost` and `WebCanvasController` |
| The resource handler carries a whole environment root (`WebRendererResourceHandler.swift:16-23,127-133`) only to serve three known HDRs, and `KhronosEnvironments.bundledDirectory` (`AppLook.swift:21`) exists only for this | Resolve `/environments/<stem>.hdr` with `KhronosEnvironments(rawValue:)?.bundledURL` and delete `environmentRoot` and `bundledDirectory`. Tighter: `LICENSES.md` is no longer servable |
| Dead routes: bare `/model` (`:79-81`; the page always fetches `/model/<name>`, `WebRendererHost.swift:160`), the `hdr` MIME case (`:150`; nothing in the renderer root is `.hdr`), and the page's `stage` field on `error` events (`viewer.html:66,679,681`; Swift ignores it) | Delete them |
| The comment "Orbit, dolly and pan are handled here…" (`viewer.html:159-165`) sits above the overlay code, not above `installPointerControls` (`:405`) | Move it |

**Risk:** low. **Verify:** `WebRendererHostTests`, `WebCanvasControllerTests`,
`PixelDiffWebKitTests` (camera pose decode), `LookProbeTests` if requested, and one real window.
**LOC:** about −40.

## I — Small core dead code

- `GLTFValidationReport.badgeTitle` and `GLTFValidationState.badgeTitle` (`GLTFValidator.swift:32-38,47-53`)
  have no callers; PreviewUI uses its own `ValidationResult`. `badgeCount` is used only in a test.
  Delete all three.
- `loadScriptSource`'s `#filePath` / cwd fallback (`:222-233`) is dead: `project.yml:134-137`
  always bundles the script into GLTFCore. It also bakes a source path into the binary. Delete it.
- `RendererKind.store` (`RendererKind.swift:23`) is used only in tests; Settings writes through
  `SettingKey.renderer`. Delete it; the test writes the defaults key.
- `AppLog.prepare` (`AppLog.swift:17`) has no users. `JointNames.synthesized` and
  `GLTFInspectorError` (used only by RealityKit) could go private, or move to RealityKit.
  `PNGWriter`'s `"StillRenderer"` domain (`PNGWriter.swift:18-21`) is a leftover name.
- **Risk:** low. **Verify:** `GLTFValidatorTests`, `RendererSwitchTests`. **LOC:** about −35.

## J — The bounds union is duplicated in RealityKit

`RendererRealityKit/PreviewCamera.swift:401-440` (`unionModelBoxes`, `longest`, `median`) is the
same outlier-filtered union as `ModelBounds.union` (`GLTFCore/ModelBounds.swift:65-101`). It
already shares the constant (`:360`). **Change:** map `BoundingBox` ↔ `ModelBounds` and call
`ModelBounds.union`. **Risk:** low. The filters match (`!isEmpty && finite`, ≥3 boxes, median ×
32); confirm that `BoundingBox.isEmpty` uses the same `max < min` rule. **Verify:**
`RealityKit/CameraFramingTests` (`:325,410`) and the RealityKit pixel diff. **LOC:** about −30.

## K — Extension and adapter dedupe

- `glb-thumb-<UUID>.png` is built in two places (`ThumbnailRealityKit.swift:12-13`,
  `ThumbnailWebKit.swift:50-51`) and matched by prefix in `ThumbnailProvider.swift:61`. Add one
  `ThumbnailProvider.outputURL()`.
- Two near-identical Quick Look failure views (`QuickLookRealityKit.swift:94-104`,
  `QuickLookWebKit.swift:130-141`). Share a `QuickLookFailureView(message:foreground:)` in the
  renderer-free `PreviewViewController.swift`. The foreground stays a parameter: RealityKit's
  depends on the stored backdrop.
- `WebDocumentWindow.canvas` repeats `CanvasStatusView(...).onAppear { register(nil) }` three
  times (`:82-103`). Use one helper.
- **Risk:** low. **Verify:** build both appexes and run `dev.sh test`. **LOC:** about −25.

## M — *(optional)* `viewer.html` overlays into a module

Lines 166–403 of `viewer.html` (about 240 of its 686 lines) are a self-contained GL line overlay:
floor, gizmo, wireframe and selection AABB. Moving them to `overlays.js`, imported by the page
module, gives the same single page with a smaller main script. The 2026-09-30 research proposed
this; it was not done. **Risk:** medium; the page loads under the scheme handler (MIME
`text/javascript` is already mapped). **Verify:** WebKit pixel diff plus `WebRendererControlsTests`
(floor, gizmo, wireframe, selection). **LOC:** about 0. Do it only if the page will grow.

---

## Unresolved questions

- **F:** the in-canvas failure chrome is a safety net nobody currently sees. Deleting it is
  behaviour-preserving today. Product could still prefer to keep it as a defensive fallback.
- **H:** delete the two `thumb-bench` tests, or gate them? The numbers live in the ledger, so
  deletion is recommended.
- **C1:** the `maxTextureEdge` edge-case fix is a visible (correct) change to Quick Look facts on
  some `.gltf` files. Call it out in the commit.
- **J:** confirm that RealityKit's `BoundingBox.isEmpty` matches `ModelBounds.isEmpty`; run the
  framing tests.
