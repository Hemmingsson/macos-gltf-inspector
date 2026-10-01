# Tidy ledger

Rejected, deferred or doubtful tidy ideas, so later research rounds do not re-propose them. One
line each: what, why.

## W1 core-webkit

- Kept `GLTFValidationReport.isClean`: only tests read it now that the badges are gone, but it is the report's one summary predicate; revisit with the validator surface.
- Deferred `JointNames.synthesized` / `GLTFInspectorError` to private or RealityKit, and `PNGWriter`'s `"StillRenderer"` error domain (chunk I extras): crosses into the realitykit lane / renames a domain; not dead code.
- Deferred chunk F live parts to wave 2 with the file split: `reset()` → `fit()`, the second load-copy re-show after `start`, and the stale "First step of the viewport migration" header on `WebPreviewCanvas`.
- Kept `WebPreviewCanvas.dismantleNSView(first, coordinator:)` in `WebCanvasControllerTests.remountAdoptsTheRunningPage`: it now calls the protocol's default no-op, which is what SwiftUI does on a remount; the test still proves adoption.
- `GLTFInspectorTests/RealityKit/CameraFramingTests.swift` gained `@testable import GLTFCore`: it builds `GLTFSessionDocument.Camera` values, whose memberwise init is now internal (D).

## W1 host

- F2.3 publish `canvasState.isReady ? viewport.commands : nil` (`DocumentShell`) — deferred: a behaviour change (menus disabled while loading), not a deletion; belongs with chunk C/F or a ticket. Today commands of the last ready canvas stay registered while the next document loads.
- `RendererAvailability.canHideNodes`, `\.shellPanelChrome`, `Availability.hasSkin` — out of W1 scope by plan (chunks C / E).
- Optional JSON-only transform/euler assertion on `EngineSelectionModel.detail` (to replace deleted `SelectionDetailTests`) — not added: tests-only addition, not a delete; camera/light/mesh detail stays covered by `EngineViewportRealityKitTests`. Candidate for the tests lane.
- `@State private var playbackController = EngineAnimationPlaybackController()` still allocates an empty controller + `RealityClipPlayer` per `RealityDocumentWindow` init (SwiftUI discards it after the first) — accepted: per parent re-init instead of per body; a lazy optional would bring back the `??` branch.
- Lane overlap: chunk A/B touched `GLTFInspector/RealityKit/{EngineSceneModel+RealityKit,PreviewView,HostPreviewContainer,RealityDocumentWindow}.swift` (assigned in the host note); watch for merge conflicts with the realitykit lane.

### Bugs seen

- None in product code. Harness note: `log stream --predicate 'process == "glTF Inspector"'` also captures other worktrees' test-host apps (same process name, e.g. "open failed cube.gltf: boom"); filter the real-window check by the launched pid.

## W1 realitykit

- `PreparePipelineReport.extensionEntries` (alias of `extensionsUsed`): kept. Its only production reader is host `EngineSceneModel+RealityKit.swift:48`, which belongs to the host lane. Repoint it there, then delete the alias and its uses in `PipelineReportTests`.
- `EngineSceneModel.mapDebugChannels(_: [PreviewDebugMode])` overload (test-only, `EngineSceneModelTests.swift:208`): resolved — the host lane deleted it in W1.
- `GLTFCore/MaterialMapPresence.swift:38`: the doc comment still names the deleted `from(gltf:)`. Not edited, because GLTFCore belongs to the core lane.
- `PreviewScene` C1 items left for a later wave: `tickWhileActive` is now just `autoRotateActive`, so it can be inlined. Also open: the `clips`/`playback` state that only keeps the first-frame pose (could be one `playAnimation(...).pause()`), the prefetch generation counter vs `.task(id:)`, the duplicated opening fit, `chromeTint(active:)` (always `true`), `isHost`/`showsInlineChrome`, and the init plumbing. None of these is a pure deletion, and they need a real-window check.
- `AnimationSampling.hasPositiveDuration` (RealityKit) and `GLTFDocumentJSON` animation duration (GLTFCore, around line 530) repeat the same min/max/sampleCount loop. Merging them crosses the core lane, so deferred.
- Bugs seen: `[load] tight float mesh convert failed: ResourceError(... invalid(vertexBufferCount: 5))`. `TightLowLevelLayout.make` (`Convert/RealityKitConvert+Mesh.swift` around line 535) gives every attribute its own vertex buffer: position, normal, tangent, uv0, uv1, color. That is up to 6 buffers. `LowLevelMesh.Descriptor` rejects 5 (the limit seems to be 4), so a mesh with position + normal + tangent + uv0 + (uv1 or color) fails the fast path. It then falls back to the `MeshDescriptor` path, which is slower and logs an error. A fix would interleave attributes into at most 4 buffers.

## W1 ui

- Deferred C2's `OutlinerList` perf tidy (`sections` rebuilt 3–4× per body, `treeIdentity` flatten per render): not a deletion; wave 2.
- Kept `MockSettingsStore`'s `defaults*` dictionaries: with `promoteToDefault` gone nothing writes them (`default(for:)` always returns the fallback), but C3 deletes the whole mock; simplify there if C3 keeps it.
- Kept `DSListRow` / `DSTypeIcon` `isSelected:`: NodeRow no longer passes it, but it is DesignSystem API the catalog shows (custom-row selection look).
- Kept the single-child `HStack` in `NodeRow.body`: it carries `.accessibilityElement(children: .contain)` and `.onHover`; removing it is not a pure deletion.
- Left the stale `PreviewUI.Theme` mentions in `DS+Color.swift:88, 126` for C9 (stale comments, wave 3).
- Crossed into GLTFCore for one line: `AppGroupSettings.Key.showToolbar` went with `SettingKey.showPills` (only `AppGroupSettingsTests` compared them; no other reader).
- Deleted the `promoteToDefault` tests (`environmentKeyPromoteWritesAppLook`, `canvasPromoteWritesUserDefaults`): the App Look / UserDefaults routing they covered is still covered through `EngineAppDefaultsBridgeTests.environmentKeysWriteAppLookNotUserDefaults`.

## W0b uitest

- Ready signal: host-only `canvasReadyMarker` (`GLTFInspector/CanvasReadyMarker.swift`) — a 1×1 clear AX element `canvas-ready`, label = renderer raw value, present only while the canvas has content (RK: convert landed and canvas mounted; WebKit: `WebCanvasController.phase == .ready`). No PreviewUI edit. Rejected: putting it on `CanvasStatusView` (PreviewUI, and its `.ready` case is the canvas region state, which for WebKit is `.ready` before the page draws).
- RK "ready" is convert + mount, not a proven first Metal frame; good enough for open-to-content trend, not a first-pixel number.
- `waitForExistence` re-polls about once a second, so open-to-content polls `exists` in a tight loop instead (no sleep); otherwise numbers round up by ~1 s.
- Open-to-content includes process launch (XCTClockMetric from `launch()`), BoxAnimated.glb, 3 iterations. First run: RK ≈ 1.15 s, WebKit ≈ 1.9 s (first iteration 2.9 s — cold page; RSD 38 %). Launch (first frame responsive) ≈ 0.40 s.
- Settings flow can only restore the App Group renderer through the UI (the test runner cannot write the host's group suite); `tearDown` re-selects the original if the test stopped midway. Stored value read from the picker, so it works whatever the user has set.
- Doubt: the WebKit open screenshot shows the box very close (fills the canvas) vs RK's fitted framing — looks like the page's initial camera, not a test issue; not investigated here.
- View-mode flow ~20–27 s per renderer, mostly XCUITest menu idling; acceptable for an opt-in suite.
- Rejected: a test plan for opt-in (a separate scheme is simpler with xcodegen and keeps `dev.sh test` untouched).
## Perf bench

Opt-in bench (dex xlrxlm4o): `./scripts/dev.sh bench` → `.build/bench/<stamp>.txt`. First
baseline was taken with other lanes building (load average 6–10), so treat it as a shape, not a gate.

- Gating: `.enabled(if: GLTF_BENCH=1)` alone still counts the skipped suite (328 vs 324), so
  `dev.sh test` also passes `-skip-testing:GLTFInspectorTests/PerfBench`. A raw `xcodebuild test`
  reports the bench as skipped.
- `tex cgimage` is about 1 ms on 2K–4K textures: GLTFKit2's `newCGImage` is lazy, so the pixel
  decode runs inside `TextureResource(image:)` and lands in `tex decode+upload`. Splitting decode
  from upload would need a forced decode (not done: it would change the product path).
- KTX2 textures (`LowLevelTexture` blit path) are not timed in `ConvertTimings`; none in the corpus.
- **Finding:** `GLTFDocumentJSON.makeDocument(json:fileURL:)` (sidebar document, built inside
  `EntityLoader.load`) is about half of RealityKit window load on the texture-heavy samples
  (~113–178 of ~230–300 ms BoomBox) and ~6.3 s on Warrior_Girl_2, where `load rest` is ~16 s
  (document + stats + whatever else `load` does outside convert — not yet attributed). Thumbnails skip it. Candidate for wave P:
  build it off the convert path / after first frame, or find what in it is slow (it is given
  `fileURL`, so likely reads the binary or image headers).
- **Finding:** web channel modes cost a one-off shader compile on first visit: in bench run 1,
  ~0.3 s on Corset, 0.5–2 s on Flame Knight / Emma Frost, 2.4–4.6 s on Porsche (41 materials).
  In run 2 (minutes later, new WebContent processes) the same first stills were 25–85 ms, so a
  compiled-shader cache survives across pages/processes (likely the system Metal/ANGLE cache;
  unverified what evicts it — run 1 followed a rebuild). F5 is real but mostly a cold-cache cost;
  measure it from a cold cache before fixing. Steady stills are 10–20 ms.
- **Finding:** web wireframe CPU per frame is 200 ms on MetalRoughSpheres (1 M tris) and ~400 ms on
  Flame Knight vs ~1–5 ms shaded (F1).
- RK `PreviewDebugMode.apply` is ~1 ms on Porsche and Emma Frost (F3 expected worse); the walks
  only hurt on node-heavy files: 350–735 ms per switch on Warrior_Girl_2 (972 k nodes). RK skeleton `updateBones` is ~90 ms per
  call on Emma Frost (F2 pass bar is 2 ms).
- Web frame times are page CPU ms (`performance.now` around `renderFrame` + overlays, 1 ms
  resolution in WKWebView), not GPU time. The bench drives frames with `still()` because an
  offscreen live page gets no rAF; real rAF pacing needs a window (XCUITest lane).
- RK first frame is an offscreen `StillRenderer` proxy (new `RealityRenderer` + IBL + one
  `updateAndRender`). The live app now logs `rk first frame uptimeMs=` from the first
  `SceneEvents.Update` after make; whether that update is the first presented frame is unverified.
- Warrior_Girl_2 is RealityKit-only (the web page would OOM on wireframe) and dominates runtime
  (~1 min per window open); `GLTF_BENCH_RUNS=1` for a quick pass.
## W2 host

- C / F3d "features once" (`DocumentWindowModel(documentURL:features:)`, `DocumentShell` reads `window.features`) — deferred: needs the two adapter roots' `init` and `DocumentShell(features:)` call sites (`GLTFInspector/RealityKit/`, `GLTFInspector/WebKit/`), owned by the realitykit / core-webkit lanes this wave. Only test-only `RendererAvailability.canHideNodes` was deleted.
- C (one seed path): accepted deltas, not visible today — the session is no longer re-seeded when a document becomes ready (environment / tone picks made from the View menu while a WebKit page is ahead of its panels are kept), and the viewport now points at the placeholder sidebar while loading instead of the previous document's.
- D: `PreviewSession+RealityKit.bindings` setters for the five settings-backed keys now pin a window override (they wrote the session only). In the window nothing writes those bindings (only the Quick Look inline chrome does, which has no `PreviewSession`), so no behaviour change.
- D real-window: the "Settings default (Floor off) seeds a new window" check was not run — the App Group suite cannot be written from a shell and driving Settings needs UI automation (uitest lane). Covered by `settingsOverlayTracksDefaultsInGetters` (session + viewport follow a changed default until pinned) and `lazyOverlayTracksDefaultsUntilOverridden`.
- E: `FixtureSceneModel.morph` (`PreviewUI/PreviewSupport/Fixtures`) lost its last caller with `CatalogComposites.inspector(model:)`; left for the ui lane (fixture library). E also touched 6 call sites in `DesignCatalog/Pages/Composites/PaneCompositePages.swift` (ui lane) — watch for a merge conflict.
- ui C6 `AppDefaultsStore.shared` / move to host — not in this lane's scope this wave.
- F: kept the "No focused window" text in both menus (plan decision) and Reset View enabled without commands (it also resets session state).
- G: morph and node names in `EngineSelectionModel.detail` were not routed through `EngineSceneModel.displayName` — see Bugs seen.
- H: optional `shouldStartUpdater` placeholder-key guard (local Release installs poll a feed they cannot verify) — behaviour change, not done.
- F10 leftovers: `ScreenshotCameraPose` → `PNGExport` rename, `EngineLookBridge` file name, `GLTFInspectorFileDocument` "GLTFKit2 needs a filesystem URL" comment — wave 3 naming.

### Bugs seen

- Inspector vs outliner names: `EngineSelectionModel.nodeDetail` / `morphDetail` use `name.isEmpty ? fallback : name` while the outliner (`EngineSceneModel.displayName`) trims, so a whitespace-only or padded node / morph mesh name shows differently in the inspector header (e.g. "  " vs "Node 3"). Fix: use `displayName` (and `EngineSceneModel.morphInfo`-style per-item builder) in both.

## W2 ui

- C5 `Dimensions.unit`: left. Every caller uses the default `"m"`; inlining it in `DimensionsReadout` is optional and not a dead field.
- C5 `MaterialInfo.emissiveStrength`: deleted as unread (host never set it). Restore from bug ticket `ijomk3wf` if the inspector should show KHR_materials_emissive_strength.
- C2 leftover: `OutlinerTree.treeIdentity` still flattens folding roots once per `OutlinerList` body for `onChange`. `sections` is now computed once; dropping the flatten would need a cheaper identity.
- C8b host `CanvasStatusView` / PreviewView loading branches: host lane, not this tree.
- C7 mock store: `[String: any Sendable]` does not compile (`as? any Sendable` is a marker-protocol cast). Uses `[String: Any]` instead.
