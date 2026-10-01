# RealityKit renderer: what is left to tidy (research)

Date: 2026-10-01 · Branch: `next-main` @ `b29ad5b` · Scope: `RendererRealityKit/` (45 files),
`GLTFInspector/RealityKit/`, `PreviewExtension/QuickLookRealityKit.swift`,
`ThumbnailExtension/ThumbnailRealityKit.swift`, `GLTFInspectorTests/RealityKit/`.
Read-only. No product code was changed.

Already done on this branch (`git log main..HEAD`), so it is **not** proposed again: prepare/temp-GLB
deleted, convert-time spec-gloss, `Texture.swizzle`, `BuildResult`, texture-transform as material
parameters, unique node names, `RealityPolicy`, thumbnail texture cap.

## Answer first

There is no large structural problem left. What remains is about 600–800 LOC of residue. It falls into
four groups:

1. **Dead or test-only API** (~250 LOC with its tests). Examples: a whole file with zero references,
   the old clip-list types, the debug-channel menu API, look helpers, report aliases.
2. **Duplicated logic.**
   - `PreviewCamera` re-implements `GLTFCore.ModelBounds.union` and `GLTFCore.CameraPreset`.
   - Host and Quick Look each have their own load-state enum and failure view.
   - The studio-IBL exponent is derived in 3 places.
3. **Leftover state in `PreviewScene`.** It still carries a whole clip-transport state machine (play, seek,
   clip index, playhead). Nothing writes to it any more: the host transport moved to
   `RealityClipPlayer`, and Quick Look has no clip UI.
4. **Long functions and files.**
   - `convert(material:)` is 185 lines, with 13 copies of a 7-line `requiredTexture` call.
   - `+Mesh.swift` mixes two mesh paths.
   - `PreviewCamera` mixes pure framing math with entity mutation.
   - `AnimationHelpers` has three near-copies of its keyframe code.

Recommended order: dead-code sweep → `PreviewScene` dead state → `PreviewCamera` dedupe/split →
loader and adapter dedupe → convert tidy. Every chunk is behaviour-preserving. The proof is
`./scripts/dev.sh test`, which includes `PixelDiffRealityKitTests` goldens, plus a real-window check
for the canvas chunks (AGENTS pitfall 9; Quick Look cannot be driven headless; see `qlmanage` memory).

## Ranked chunks

| # | Chunk | Value | Risk | Est. LOC | Files (disjoint unless noted) |
|---|---|---|---|---|---|
| 1 | A1 Dead code: convert / loader / reports | High | Low | −110 | `MaterialMapPresence+GLTFKit.swift`, `Convert/AnimationHelpers.swift`, `Convert/Skin.swift`, `Convert/RealityKitConvert*.swift` (top), `ConvertProblemReport.swift`, `PreparePipelineReport.swift`, `MaterialVariants.swift`, host `EngineSceneModel+RealityKit.swift`, tests |
| 2 | A2 Dead code: canvas-side API | High | Low | −140 | `PreviewClip.swift`, `PreviewDebugMode.swift`, `RealityLook.swift`, `ModelDimensions.swift`, `PreviewSessionBindings.swift`, host `PreviewSession+RealityKit.swift`, `PreviewQuickLookChrome.swift`, `PreviewInteraction.swift` (monitor param), tests |
| 3 | C1 `PreviewScene`: dead clip state, prefetch task, fit dedupe | High | Low–Med | −110 | `PreviewScene.swift` only |
| 4 | B `PreviewCamera`: reuse GLTFCore, split math from entity ops | Med–High | Low–Med | −90 net (+ split) | `PreviewCamera.swift` (+ new `CameraFraming.swift`), host `RealityDocumentWindow.swift` (1 line), `CameraFramingTests` |
| 5 | D Loader: scene switch + studio exponent | Med | Low–Med | −45 | `EntityLoader.swift`, `LoadedModel+Host.swift`, `Convert/RealityKitConvert.swift` (BuildResult), host `RealityDocumentWindow.swift` (reloadScene), tests |
| 6 | E Adapters: shared load state, still entry point | Med | Low | −90 | host `PreviewView.swift`, `PreviewExtension/QuickLookRealityKit.swift`, `StillRenderer.swift`, `LiveStillRequest.swift`, `RealityThumbnail.swift`, host `ScreenshotCameraPose+RealityKit.swift`, still tests |
| 7 | G Convert: material + animation tidy | Med | Low | −110 | `Convert/RealityKitConvert+Material.swift`, `Convert/RealityKitResourceContext.swift`, `Convert/AnimationHelpers.swift`, `Convert/RealityKitConvert+Animation.swift` |
| 8 | F Convert: split / tidy `+Mesh.swift` | Med | Low–Med | −60 (+ split) | `Convert/RealityKitConvert+Mesh.swift` (+ new `+LowLevelMesh.swift`) |
| 9 | C2 `PreviewScene`: one session object instead of 12 local `@State`s | Med | Med | −40 net | `PreviewScene.swift`, `PreviewSessionBindings.swift` (after C1, A2) |
| 10 | H Isolation and visibility | Low–Med | Low | −45 annotations | `PreviewSelectionVisuals`, `PreviewSkeletonOverlay`, `PreviewFloor`, `PreviewLighting`, `PreviewMorph`, `GLTFNodeIDComponent`, `PreviewHosting`/`PreviewInteraction` (monitor), `PreviewBackground`, `project.yml` comment |
| 11 | J Tests tidy | Low | Low | −40 | `GLTFInspectorTests/RealityKit/*` |
| 12 | I Naming (optional) | Low | Low (churn) | ±0 | wide |

Dependencies:
- A2 before C2: both touch `PreviewSessionBindings`.
- C1 before C2: same file.
- B owns every `PreviewCamera.swift` edit, so A2 leaves `PreviewCamera.dimensions` / `fieldOfViewRange` to B.
- D and E both touch `RealityDocumentWindow.swift`, but in different functions. Run them in sequence or rebase.
- The rest can run in parallel worktrees.

---

## Chunk A1: dead code in convert, loader and reports (low risk)

All of these were checked with `grep -w` across the whole repo, tests included.

| Finding | Evidence | Change | LOC |
|---|---|---|---|
| `MaterialMapPresence.from(gltf:)` has **zero** references. The document now builds map presence from JSON. | `RendererRealityKit/MaterialMapPresence+GLTFKit.swift:6` (whole file) | Delete the file | −36 |
| `AnimationSampling.documentedDuration` is never called | `Convert/AnimationHelpers.swift:65-72` | Delete | −8 |
| `ConvertProblem.Code.defaultMaterial` is never recorded. `context.defaultMaterial` is an unrelated property. | `ConvertProblemReport.swift:8` | Delete the case | −1 |
| `PreparePipelineReport.isEmpty`, `showsInSidebar`, `extensionEntries`: no production reader. `extensionEntries` is a pure alias of `extensionsUsed`. `LeftSidebar.isEmpty` is PreviewUI's own `PipelineReport`. | `PreparePipelineReport.swift:17-24,47`; host `EngineSceneModel+RealityKit.swift:48`; `PipelineReportTests.swift:46-48` | Make `extensionsUsed` `public private(set)`. Delete the three members and point host and test at `extensionsUsed`. | −12 |
| `MaterialVariants.names(from:)` is test-only (names now come from JSON, `GLTFDocumentJSON.materialVariantNames`). Its header still says "Spike helpers". | `MaterialVariants.swift:4-15`; `MaterialVariantsTests.swift:17` | Delete. Assert on `model.materialVariantNames` in the test. Fix the doc comment. | −10 |
| `Skin.resolvedName` is a one-line wrapper over `GLTFCore.JointNames.resolved`. The `targetNode.isJoint` fallbacks in animation (`name`, `nextUniqueName("joint")`) are unreachable: GLTFKit2 sets `isJoint` only while it adds the node to a skin's `joints` (`GLTFAssetReader.m` `convertSkins`), so `Skin.jointIndex` never returns nil there. `sourceAsset` is optional but always set. | `Convert/Skin.swift`; `Convert/RealityKitConvert+Animation.swift:44-51`; `RealityKitConvert.swift:38,60` | Inline `jointIndex` and call `JointNames.resolved` directly. Keep one `?? 0` guard instead of two dead branches. Pass `asset` instead of storing `sourceAsset?`. Delete `Skin.swift`. | −20 |
| `PlatformColor` typealias (macOS only) and `UniqueNameGenerator` class (a dictionary in a class behind a forwarding method) | `RealityKitConvert.swift:10-33` | Use `NSColor`, and a `[String: Int]` counter in `nextUniqueName` | −15 |
| `TransformSampler(maximumSampleInterval:)` is always `1/30` (`// TODO: Make sample interval an option`). `convertMorphWeights` hard-codes `1 / 30` instead of `AnimationSampling.defaultInterval`. | `+Animation.swift:42,147` | Drop the parameter and use `defaultInterval` | −5 |
| Host `EngineSceneModel.mapDebugChannels(_: [PreviewDebugMode])` overload is test-only | `GLTFInspector/RealityKit/EngineSceneModel+RealityKit.swift:74-76`; `EngineSceneModelTests.swift:208` | Delete. The test maps with `.map(\.renderViewMode)`. | −4 |

**Verify:** `dev.sh test` (AnimationSamplingTests, MorphSkeletonTests, PrepareFreeInputsTests
`unnamedJointSkin`, MaterialVariantsTests, PipelineReportTests, ConvertProblemTests).

## Chunk A2: dead or test-only canvas-side API (low risk)

| Finding | Evidence | Change | LOC |
|---|---|---|---|
| `PreviewClip.list(from:)`, `PreviewClipInfo`, `PreviewClip.info` are test-only (leftovers of the old seam Availability) | `PreviewClip.swift:16-19,51-62,70-75`; `PreviewClipTests.swift:8-19,29+`; `SessionDocumentConvertTests.swift:104-107` | Delete, plus the tests that only compare `usable` to `list`. Keep the `usable` title tests. | −45 |
| `PreviewDebugMode.shortTitle`, `channelID`, `labels(for:)`, `availableDebugChannels(from:)`, `PreviewDebugChannel`: production now goes `renderViewMode` → PreviewUI. Only tests read these. | `PreviewDebugMode.swift:14-31,100-106,142-170`; `PreviewDebugModeTests.swift:7-15,189+` | Delete, and assert on `renderViewMode` in the tests | −50 |
| `PreviewDebugMode.apply(_:to:store:)` 2-arg overload is test-only | `PreviewDebugMode.swift:108-110` | Delete. Tests pass `doubleSided: false`. | −4 |
| `RenderLook.realityKitIBLYaw` / `realityKitIBLExponent(fileHasLights:)` are test-only. Production calls `RealityLook.iblExponent` directly (`PreviewScene.swift:207-212`, `LiveStillRequest.swift:29`). | `RealityLook.swift:53-67`; `EmissiveBoostTests.swift:77-84` | Delete the extension. The test calls `RealityLook.iblYaw` / `iblExponent`. | −15 |
| `PreviewSessionBindings.debugModes` is stored but never read. The canvas uses `model.debugModes`. | `PreviewSessionBindings.swift:19-20,35,49`; host `PreviewSession+RealityKit.swift:39` | Delete the field and its init param. The host still uses `modes` inside the index closure. | −5 |
| `PreviewQuickLookChrome(isDark _:)` takes a parameter it ignores (the comment admits it) | `PreviewQuickLookChrome.swift:10-14`; caller `PreviewScene.swift:418` | Drop the parameter and use the memberwise init | −5 |
| `PreviewOrbitDragMonitor.install(hitTestBounds:)` is always `true` (one caller) | `PreviewInteraction.swift:255,268`; `PreviewHosting.swift:37` | Drop the parameter and the `if` | −4 |
| `PreviewInteraction.suppressesAutoRotate` is a pure alias of `isCameraGesturing` | `PreviewInteraction.swift:79` | Read `isCameraGesturing` (one caller, `PreviewScene.swift:485`) | −2 (touches C1's file: leave to C1 if run in parallel) |

**Verify:** `dev.sh test` (PreviewClipTests, SessionDocumentConvertTests, PreviewDebugModeTests,
EmissiveBoostTests, EngineSceneModelTests, HostSidebarModelOverlayTests).

## Chunk C1: `PreviewScene.swift` (713 lines), dead state and duplication (low–medium risk)

1. **Dead clip transport.**
   - Evidence:
     - `isPlaying`, `isSeeking`, `clipIndex`, `clipDuration`, `currentTime`, `clips` (`:71-76`) are written only in `make`'s Task (`:290-296`). Nothing else writes them: the host transport is `RealityClipPlayer` / `EngineAnimationPlaybackController`, and Quick Look has no clip UI.
     - So these are dead: the `onChange(of: isPlaying / isSeeking / clipIndex)` handlers (`:437-455`), the playhead branch in the tick (`:495-498`), `isPlaying` in `tickWhileActive` (`:226-228`) and most of `startClip` (`:590-602`).
     - The one live effect is that clip 0 starts paused at t = 0, which poses the model on its first frame.
   - Change: keep that effect as one line in `make`'s Task, e.g. `entity.playAnimation(first.resource.repeat()).pause()`, plus the existing log. Delete the rest. `tickWhileActive` becomes `autoRotateActive`.
   - LOC: −55.
2. **Prefetch generation counter.**
   - Evidence: `onAppear` + `onChange(of: lookStore.look)` + `prefetchGeneration` + `prefetchLook` with an unstructured `Task {}` (`:82,430-433,456-458,572-584`). AGENTS lists `Task {}` in views as a pitfall.
   - Change: one `.task(id: lookStore.look) { … await PreviewLighting.prefetchLook(look); guard !Task.isCancelled …; pendingReady = look }`. Cancellation replaces the generation check.
   - LOC: −15.
3. **The same fit is written twice.**
   - Evidence: `update`'s `needsLayoutFit` block (`:308-326`) and `resetOpeningFit` (`:505-526`) both do pivot reset → `applyFit(…)` → set `appliedSessionOrthographic` / `appliedFieldOfViewDegrees`.
   - Change: one `applyOpeningFit(_ camera:)` helper.
   - LOC: −15.
4. **Redundant inner `.id(centerModelValue)`** (`:401`).
   - Evidence: `RealityPreviewCanvas` already re-identifies the whole scene on `centerModel` (`:704`). Quick Look never toggles Center.
   - Change: delete the inner `.id`.
   - LOC: −2.
5. **Sidebar document fallback.**
   - Evidence: `documentSkins` (`:203-206`) and `applyFileCamera` (`:529-541`) read `sidebar.document`, but the host adopts `model.document` (`RealityDocumentWindow.swift:162`) and a scene reload keeps it.
   - Change: read `document` only.
   - LOC: −5.
6. **Small items.**
   - `isHost` + `showsInlineChrome` mean the same thing (`:133-136`).
   - `chromeTint(active:)` is only ever called with `true` (`:586-588`).
   - `DebugAppliedIndex` is a 2-field class beside `PreviewFrame` (`:660-663`): fold it into `PreviewFrame`.
   - LOC: −12.
7. **Plumbing.**
   - Evidence: `PreviewScene.init` takes 5 model fields (`entity`, `document`, `stats`, `debugModes`, `studioIBLExponent`) only so `RealityPreviewCanvas` can unpack `LoadedModel` (`:87-108,691-703`).
   - Change: take `model: EntityLoader.LoadedModel`.
   - LOC: −20.
8. **Stale comment.**
   - Evidence: `:466` cites "AGENTS.md pitfall 4". Pitfall 4 is now "One renderer, relative URLs"; the RealityView rule is pitfall 8.
   - Change: fix or drop the reference.

**Verify:**
- `dev.sh test` (no test constructs `PreviewScene`, so this is compile-only).
- Real window (pitfall 9) on `BoxAnimated` and a skinned sample:
  - the first-frame pose matches before and after;
  - play, pause and seek still work from the host transport;
  - Fit, Reset, Center toggle, ortho toggle, look change (HDR swap) and a backdrop cycle all still work;
  - "Modifying state" count ≈ 0.
- Quick Look: open an animated `.glb` in Finder and check that it shows the same first-frame pose.

## Chunk B: `PreviewCamera.swift` (702 lines), reuse GLTFCore and split (low–medium risk)

| Finding | Evidence | Change | LOC |
|---|---|---|---|
| `unionModelBoxes` + `median` + `longest` + `outlierExtentRatio` re-implement `GLTFCore.ModelBounds.union` line for line (same ≥ 3 / median × 32 rule) | `PreviewCamera.swift:357-441` vs `GLTFCore/ModelBounds.swift:65-101` | Map `BoundingBox` ↔ `ModelBounds` and call `ModelBounds.union`. Check that `BoundingBox.isEmpty` matches `any(max .< min)` (unit test with an empty box). | −40 |
| `modelBounds` inlines the helper-name list with a stale reason ("Inline names — ThumbnailExtension excludes PreviewFloor.swift"). `PreviewFloor.isHelperName` exists and every file is in one framework now. Same staleness in the `worldOriginGizmoName` comment ("so ThumbnailExtension can compile") and in `PreviewSkeletonOverlay.swift:9`. | `PreviewCamera.swift:23-25,371-382` | Call `PreviewFloor.isHelperName`. Drop the stale comments. | −8 |
| `PreviewCamera.CameraPreset` duplicates `GLTFCore.CameraPreset`. The host maps between them by raw string (`RealityDocumentWindow.swift:96`). `title`, `menuSymbol`, `id`, `Identifiable`, `CaseIterable` are unused: the host has its own `HostViewMenuCommands.menuSymbol(for:)`, and the doc comment says "throwaway View menu". | `PreviewCamera.swift:29-71` | `extension GLTFCore.CameraPreset { var yawDegrees; var pitchDegrees }` (internal). `reframe(preset: CameraPreset?)` takes the core type. The host passes `$0` straight through. | −30 |
| Wrapper constants: `fieldOfViewRange` (test-only), `clampedFieldOfView`, `defaultFieldOfViewDegrees` forward to `RenderCamera` | `:7-9,227-229` | Use `RenderCamera` directly | −8 |
| `applyFit` builds a whole `PerspectiveCamera` entity (`makeFrontThreeQuarter`) only to read its position | `:162-172` | Call `cameraPosition(…)` | −8 |
| 4 `orthographicScale` overloads | `:233-304` | Keep the (bounds, eye, target) form and the private extent form. Callers with no eye use `cameraPosition` | −20 |
| One file mixes **pure framing math** (thin axis, look direction, projected AABB, fit distance, ortho scale, clip distances: all nonisolated) with **entity mutation** (turntable, gizmo, apply*, file view) | whole file | Split the pure math into `CameraFraming.swift` (nonisolated, what `CameraFramingTests` mostly exercises). `PreviewCamera.swift` keeps the `@MainActor` entity ops. | ±0 (split ~300 / ~300) |
| `PreviewCamera.dimensions(of:relativeTo:)` is test-only | `ModelDimensions.swift:29-38`; `ModelDimensionsTests.swift:24` | Delete. The test uses `model.extent.dimensions`. | −10 |

**Verify:**
- `dev.sh test`: CameraFramingTests (414 lines, framing math), StillCameraPoseTests, StillRenderProofTests, JSONModelBoundsRealityKitTests, and the `PixelDiffRealityKitTests` thumbnail framing goldens. The math is identical, so goldens must be bit-stable.
- Real window: View ▸ presets, Fit, ortho.

## Chunk D: loader, scene switch and studio exponent (low–medium risk)

1. **Scene-switch API has three layers.**
   - Evidence: `EntityLoader.convertScene` (`EntityLoader.swift:122-136`) → `loadScene` + `ConvertedScene` (an opaque box around `Entity`) → `LoadedModel.replacingScene` (`LoadedModel+Host.swift:26-60`). The host calls `loadScene` and then `replacingScene` (`RealityDocumentWindow.swift:246-255`).
   - Change: one `public func LoadedModel.switchingScene(to index:, from url:, materialVariantIndex:) async throws -> LoadedModel`, with the same retained document, stats and reports. Delete `ConvertedScene` and `loadScene`. `convertScene` can become private, with tests going through the new method.
   - LOC: −25.
2. **Studio exponent is derived three times.**
   - Evidence: `punctualLightCount(in:)` walk + `RealityPolicy.studioIBLExponent` in `load` (`:187-190`), in `loadThumbnail` behind an extra `await MainActor.run` hop (`:111-115`), and in `replacingScene` (`LoadedModel+Host.swift:34-36`).
   - Change: count lights during convert (`RealityKitConvert.convert(node:)` already switches on `gltfNode.light`). Return `studioIBLExponent` in `BuildResult`. Delete the walk and the hop.
   - LOC: −20.
   - Tests: `SceneGraphConvertTests:12,51` assert on `punctualLightCount`; assert on `model.studioIBLExponent` instead.
3. Not proposed: `includeAnimations` on `load` is passed only by tests, which use it for speed. Leave it.

**Verify:**
- `dev.sh test`: SessionDocumentConvertTests (multi-scene, 1020), SceneGraphConvertTests, EmissiveBoostTests, PipelineReportTests (studio-dim line).
- Real window: scene picker on a multi-scene file; the lights dim line is unchanged.
- Update `docs/pipeline-gltf-to-realitykit.md` §"Scene switch" (`convertScene(…)` → new name).

## Chunk E: adapter duplication (low risk)

1. **Load state is written twice.**
   - Evidence: `PreviewView.State` + `failedView` (`GLTFInspector/RealityKit/PreviewView.swift:9-26,72-88`) and `QuickLookRealityView.State` + failure body (`PreviewExtension/QuickLookRealityKit.swift:65-108`) are the same enum, the same `loaded(from:)` and the same two-line failure view.
   - Change: move a `public enum RealityLoadState` and a `RealityLoadStateView(state:interaction:isDark:background:)` (spinner / canvas / failure) into RendererRealityKit. Both adapters keep only their hosting code.
   - LOC: −40.
2. **Still rendering takes four hops.**
   - Evidence:
     - The path is host `ScreenshotCameraPose.renderReality` → `LiveStillRequest.init` → `.render` → `StillRenderer.renderImage` → `StillRenderer.init(cameraPose:)` → `capture()`.
     - `LiveStillRequest` was split so the pose could be captured *before* the save panel. The host now renders first and then opens the panel (`ScreenshotCameraPose.swift:11`, `EngineViewportController.swift:225-231`), so that reason is gone.
     - Every `StillRenderer` use (2 production, 7 test) is init → `capture()` once.
   - Change:
     - `StillRenderer` becomes an enum with `static func render(root:bounds:…)` and `render(root:cameraPose:…)` sharing one private builder. This also removes the duplicated `self.renderer/texture/width/height` init tails (`StillRenderer.swift:90-148`).
     - `LiveStillRequest` becomes one `public static func renderLiveStill(interaction:exposureEV:dimStudioForFileLights:backdropIndex:environmentYaw:aspect:)`.
   - LOC: −45.
3. **Two playback-controller inits.**
   - Evidence: `RealityDocumentWindow` builds a `RealityClipPlayer` only to log its clips, then wraps it with `init(player:)` (`:159-169`). `applyReloaded` uses `init(loaded:)` (`:233`).
   - Change: use `init(loaded:)` in both places and log `controller.clips`.
   - LOC: −3.
4. **Pipeline-report kind found by substring match.**
   - Evidence: host `mapPipelineReport` sets `kind` with `line.contains("File lights") || line.contains("Studio IBL")` (`EngineSceneModel+RealityKit.swift:41-46`). That couples it to the English text in `PreparePipelineReport.entries`.
   - Change: expose `lightingEntry: String` and `conversionEntries: [String]` (or a typed entry) from the report.
   - LOC: −2, but removes a hidden coupling.
5. **Possibly unneeded `Task { @MainActor in }`.**
   - Evidence: `resetPreviewView` (`RealityDocumentWindow.swift:120-123`) wraps a counter bump in this Task. The function runs on the main actor already, from a menu or command closure.
   - Change: probably removable. Check that no caller invokes it during a view update. Leave it if unsure.

**Verify:**
- `dev.sh test`: StillRenderProofTests, PixelDiffRealityKitTests, StillCameraPoseTests, AnimationSamplingTests, TextureTransformConvertTests, PrepareFreeInputsTests, EngineViewportRealityKitTests.
- `./scripts/proof.sh`.
- Real window: Export PNG.
- Quick Look: open a good file and a broken file.

## Chunk G: convert, material and animation tidy (low risk)

1. **`convert(material:)` is 185 lines** (`RealityKitConvert+Material.swift:16-200`). It contains 13 copies of `context.requiredTexture(for:channels:semantic:materialName: name)`, 7 lines each.
   - Change: a local `func tex(_ p: GLTFTextureParams, _ c: ColorMask, _ s: Semantic)` closure, with each call on one line. Split into `makeUnlit` / `makePBR`.
   - LOC: −70.
2. **`RealityKitResourceContext` small items.**
   - `cachedConvertedMaterial` / `storeConvertedMaterial` are one-line dictionary wrappers.
   - `ColorMask: Int` declares a raw type nothing uses.
   - `init` uses `fatalError` plus a `makeCommandQueue()!` force-unwrap (`:58-141`). Make it `init?` / `throws` and surface it as error 1022.
   - LOC: −10.
3. **`AnimationHelpers.swift` (363 lines) repeats itself.**
   - `AnimatedVector3` and `AnimatedQuaternion` (`:142-209`) repeat the same keyframe lookup / step / cubic-index structure; only the interpolation differs.
   - `TransformSampler.init` repeats one 12-line block three times (`:283-323`).
   - `glbLerp`, `glbUnlerp`, `glbCubicInterp` are module-global (`:81-104`).
   - `AnimatedWeights.recommendedSampleInterval` clamps, then `convertMorphWeights` clamps again, then `sampleTimes` clamps a third time.
   - Change: one `channel(times:values:default:)` helper, `fileprivate` free functions, a single clamp, and `struct` for the `final class` samplers.
   - LOC: −40.

**Verify:** `dev.sh test` (LoaderMaterialTests, TextureTests, EmissiveBoostTests, TextureTransformConvertTests,
AnimationSamplingTests (densify, cubic, step), MorphConvertTests, MorphSkeletonTests, PixelDiffRealityKitTests).

## Chunk F: split and tidy `RealityKitConvert+Mesh.swift` (704 lines; low–medium risk)

- The file holds two mesh paths:
  - `MeshResource.Contents` for skin, morph and points: `:11-104`, `:297-467`.
  - `LowLevelMesh` for static meshes: `:106-295`, `:469-703`.
- **Split.** Move the `LowLevelMesh` path to `Convert/RealityKitConvert+LowLevelMesh.swift`, about 330 lines each. Pure move.
- **Names are now misleading.** `convertTightFloatMesh`, `TightMeshPrimitivePlan`, `TightLowLevelLayout` and `makeTightMeshPrimitivePlan` take *any* static accessor now (the docs say "now any static accessor"). Rename them to `LowLevel*`. The header comment at `:8-9` names `tightFloatAccessor`, which no longer exists.
- **`TightMeshGatherResult`** (`:516-521`) carries `hasNormals`, `hasTangents` and `hasColors`, all of which can be derived from the plan. Delete it and compute `any*` with `plans.contains { $0.normals != nil }`.
- **Unused parameter.** `positionBounds(_:_ positions:)` ignores `positions` and re-packs with `Packed.float3Array` (`:273-283`). Drop the parameter, or compute the bounds from the already-packed data, which saves a second copy for quantized meshes.
- **Repeated fill closures.** Four near-identical `fillLowLevelVertexBuffer` closures (`:165-243`) do "copy or zero / white". Replace them with one `copy(_ bytes:, or fill:)` helper.
- **Leftovers.** The `jointInfluences` reduce becomes `flatMap` (`:389-397`). Drop the vendored `TODO`s at `:90,405`.
- LOC: −60.
- **Verify:**
  - `dev.sh test`: PixelDiffRealityKitTests, PrepareFreeInputsTests (quantized quad), InstancingTests, MorphConvertTests, TextureTransformConvertTests (UV1 on LowLevelMesh), PipelineHoleTests, CameraFramingTests (bounds).
  - Perf: this is a pure refactor of the EXP-017 path, so no re-bench is needed. One `load-bench` control run is optional if the fill helper changes copy granularity.

## Chunk C2: one session state for Quick Look (medium risk; after A2 and C1)

- **Problem.**
  - `PreviewScene` has 12 `@State local*` copies of the host session (`:50-66`), 12 `session?.x ?? $localX` binding properties (`:138-184`), 9 `*Value` read properties (`:192-202`) and their seeding in `init` (`:112-129`).
  - The only reason is Quick Look, where `session == nil`.
- **Change.**
  - Add an internal `@Observable final class LocalPreviewSession` in RendererRealityKit. It is seeded from `AppGroupSettings` (auto-rotate, floor, backdrop), with `dimStudioForFileLights = studioIBLExponent < 0`, and exposes `bindings: PreviewSessionBindings`, mirroring the host's `PreviewSession.bindings`.
  - `RealityPreviewCanvas` holds `@State var local = LocalPreviewSession(...)`. This is initialised with `State(initialValue:)` only (pitfall 1) and is fresh per model, because the canvas is re-identified per entity.
  - It passes `session ?? local.bindings`. `PreviewScene.session` becomes non-optional and reads `session.x.wrappedValue`.
- **LOC.** −110 in `PreviewScene`, +45 new, so about −65 net (≈ −40 after C1 overlap).
- **Risk.** Medium. This is SwiftUI dependency tracking: the reads move from `@State` to `@Observable` through bindings, so check that `RealityView.update` still fires on a Quick Look backdrop or auto-rotate toggle.
- **Verify.**
  - Compile.
  - Real Quick Look: the backdrop cycle and auto-rotate toggle redraw, and the floor tint follows the backdrop.
  - Host window: every session control still drives the canvas.
  - Pitfall 9 log: "Modifying state" ≈ 0.

## Chunk H: isolation and visibility (low risk, compiler-checked)

- **Per-function `@MainActor` (96 in RK).**
  - Evidence: `PreviewSelectionVisuals`, `PreviewSkeletonOverlay`, `PreviewFloor`, `PreviewLighting`, `PreviewMorph` and `GLTFNodeLookup` are enums where nearly every function is `@MainActor`.
  - Change: put `@MainActor` on the type and mark the few pure helpers `nonisolated` (`isHelperName`, `lineMaterial`, `makeCircleRingMesh`, `loadEquirectangular`, `morphName`).
  - LOC: about −45 lines of annotations.
- **Public API with no consumer outside the module.**
  - `PreviewLighting` (`public enum`).
  - `PreviewOrbitDragMonitor` and its `install` / `remove`.
  - `PreviewBackground.storedIndex`.
  - `PreviewCamera.clampedFieldOfView` and `defaultFieldOfViewDegrees`, unless B has already removed them.
  - Change: make them internal.
- **Small leftovers.**
  - `PreviewLighting.loadEquirectangular` (`:161-163`) is a one-line forward to `EquirectangularImage.load`.
  - `studioHDRName` is used only in a log message.
- **Stale comment in `project.yml:155`.** "glTF → GLTFKit2 → **prepare** → convert": the prepare pass is gone.
- **Verify:** clean build of all three targets (host and both appexes) plus `dev.sh test`.

## Chunk J: tests (low risk)

- `appendPreviewClipFloats` (`PreviewClipTests.swift:127-132`) duplicates the shared `appendFloats` (`TestGLBFixtures.swift:286`).
- Misfiled tests:
  - `LoaderMaterialTests.swift` declares `struct LoaderHelpersTests`.
  - The `RealityLook` tests (`iblExponentAddsExposure…`, `renderLookMapsToRealityKitUnits`) live in `EmissiveBoostTests.swift`. Move them to `RealityLookTests.swift`.
- Tests that assert implementation details:
  - `SceneGraphConvertTests.orthographicCameraConverts` (`:61-67`) and `livePerspectiveCount` (`:71-77`) assert that convert creates camera components which `PreviewCamera.makeTurntable` → `disableCameras` then strips (`PreviewCamera.swift:443-455`). File cameras are viewed from the JSON document (`applyFileCamera`).
  - Optional follow-up: stop converting cameras at all (`RealityKitConvert.swift:159-161,242-258`) and delete `disableCameras`. Assert on the document instead.
  - The risk is medium–low: `PixelDiffRealityKitTests` renders `model.entity` without the turntable, with an explicit `activeCamera`, and the goldens prove it.
- `RealityRendererFeatureTests` checks that a constant equals itself (`features == allCases`). Keep it as intent, or delete it.
- `entity(nodeIndex:in:)` in `RealityTestHelpers.swift:60-63` is a one-line forward to `GLTFNodeLookup.entity`.

## Chunk I: naming (optional, churn only)

- **The `Preview*` prefix means two things.** The RK framework uses it for RK-only types (`PreviewScene`, `PreviewCamera`, `PreviewLighting`, `PreviewInteraction`, `PreviewSessionBindings`, …). Host files use it for PreviewUI / neutral types (`PreviewSession`, `PreviewFocus`). Newer RK types already use `Reality*` (`RealityPreviewCanvas`, `RealityClipPlayer`, `RealityLook`, `RealityPolicy`, `RealityThumbnail`).
- **Worth doing now:**
  - `PreparePipelineReport` → `RealityPipelineReport`. The prepare pass is gone, and the name sits next to PreviewUI's `PipelineReport`.
  - Host `GLTFInspector/RealityKit/PreviewView` → `RealityCanvasView`. It is easily confused with PreviewUI.
- **Defer** the wide rename until no parallel worktrees touch RK.

---

## Suspected bugs found in passing (not behaviour-preserving; out of scope; worth a ticket)

1. **Fit resets the field of view to 35°.**
   - Evidence: `PreviewInteraction.markFitted()` → `resetFOV()` (`PreviewInteraction.swift:91-95,176-179`) sets the camera FOV to `defaultFieldOfViewDegrees`. Every Fit path calls `markFitted`: the opening fit (`PreviewScene.swift:326`), `resetOpeningFit` and host `reframe`. Each of those has just applied the *session* FOV and recorded `frame.appliedFieldOfViewDegrees = session`, so `syncSessionFieldOfViewIfNeeded` never re-applies it.
   - Effect: with the FOV slider ≠ 35°, the camera snaps to 35° after a Fit while the slider keeps its value. The fit distance was computed for the session FOV, so the framing is off too.
   - Check: set FOV 60 → Fit → read the camera's `PerspectiveCameraComponent.fieldOfViewInDegrees`.
2. **Two playback controllers on one entity.** `PreviewScene` starts clip 0 paused on the entity at mount, and the host `RealityClipPlayer` later starts its own controller and never stops the first. This is probably harmless, because RealityKit's default handoff replaces it. Chunk C1 keeps this behaviour. Whether the first-frame pose is even wanted in the host is a product question.

## Unresolved

- Does `RealityKit.BoundingBox.isEmpty` use the same definition as `ModelBounds.isEmpty` (`any(max .< min)`)? Needed for B. Add a one-line unit test before swapping.
- Is the first-frame pose (clip 0 paused) intended for Quick Look and the host? C1 keeps it; deleting it would change the visible pose.
- Does `resetPreviewView`'s `Task { @MainActor in }` hop guard against a call during a view update? Keep it unless a trace shows otherwise.
