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
