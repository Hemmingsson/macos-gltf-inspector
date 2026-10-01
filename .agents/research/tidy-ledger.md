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
