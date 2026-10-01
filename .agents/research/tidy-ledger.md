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
- `EngineSceneModel.mapDebugChannels(_: [PreviewDebugMode])` overload (test-only, `EngineSceneModelTests.swift:208`): not deleted, because `EngineSceneModel*` belongs to the host lane.
- `GLTFCore/MaterialMapPresence.swift:38`: the doc comment still names the deleted `from(gltf:)`. Not edited, because GLTFCore belongs to the core lane.
- `PreviewScene` C1 items left for a later wave: `tickWhileActive` is now just `autoRotateActive`, so it can be inlined. Also open: the `clips`/`playback` state that only keeps the first-frame pose (could be one `playAnimation(...).pause()`), the prefetch generation counter vs `.task(id:)`, the duplicated opening fit, `chromeTint(active:)` (always `true`), `isHost`/`showsInlineChrome`, and the init plumbing. None of these is a pure deletion, and they need a real-window check.
- `AnimationSampling.hasPositiveDuration` (RealityKit) and `GLTFDocumentJSON` animation duration (GLTFCore, around line 530) repeat the same min/max/sampleCount loop. Merging them crosses the core lane, so deferred.
- Bugs seen: `[load] tight float mesh convert failed: ResourceError(... invalid(vertexBufferCount: 5))`. `TightLowLevelLayout.make` (`Convert/RealityKitConvert+Mesh.swift` around line 535) gives every attribute its own vertex buffer: position, normal, tangent, uv0, uv1, color. That is up to 6 buffers. `LowLevelMesh.Descriptor` rejects 5 (the limit seems to be 4), so a mesh with position + normal + tangent + uv0 + (uv1 or color) fails the fast path. It then falls back to the `MeshDescriptor` path, which is slower and logs an error. A fix would interleave attributes into at most 4 buffers.

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
