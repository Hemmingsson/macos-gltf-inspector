# Engine Feature Packs — codebase work for the new UI

Backs [DESIGN.md](DESIGN.md); feeds the seam in [UI-BUILD.md](UI-BUILD.md) §0.
**Each pack is independent and testable in the CURRENT UI now** — add a throwaway control
(menu item, toggle, print, or test) to prove it, then bind to the seam later.

> **Re-verified 2026-08-21 against `main`** (post repo-reduction commits — the earlier pass
> targeted `feature/scene-interaction-controls`, which had more in `GLTFSessionDocument`; the
> reduction passes trimmed it, so several "DONE" claims below were downgraded). Status legend:
> **DONE** = exists, only needs surfacing · **REUSE** = plumbing exists, thin wrapper ·
> **NEW** = net-new · **DECISION** = needs a call first.
>
> **Corrected headline (what actually exists on `main`):**
> - `GLTFSessionDocument` is **NOT a full parsed model.** Its own doc comment says so. It stores
>   only: `scenes`, `nodes` (**`index`/`name`/`children`/`cameraIndex?` — no TRS, no
>   `meshIndex`, no `lightIndex`, no `skinIndex`, no kind**), `cameras`, `animations`
>   (name/duration). **There is no `document.lights`, `document.materials`, `document.meshes`,
>   `document.skins`.** The rich per-node/mesh/material/light data *is* available from the
>   `GLTFAsset` (GLTFKit2) at convert time (`RealityKitConvert.makeDocument`) but is **not
>   persisted** — most of §B is *extend `makeDocument` + add struct fields*, not *surface*.
> - Selection **is** built (`HostSidebarModel.selectedNodeIndex` + `PreviewSelectionVisuals`);
>   per-node **hide** is built (`hide: Set<Int>` + `showAll()`). **Solo/isolate logic does NOT
>   exist** (no `soloRoot`/`soloHides` on `main`) — P31 must build it, not just wire a trigger.
> - Channel-presence lives in a **`private` file-scoped `struct Channels`** in
>   `PreviewDebugMode.swift` (not `PreviewDebugMode.Channels`, not public). The only public
>   consumer is **`PreviewDebugMode.available(from json:) -> [PreviewDebugMode]`**.
> - The single-source-of-truth state refactor (P33) is **already done on `main`**
>   (`PreviewScene.swift:39,94`) and `autoRotate` **is** registered (`GLBPreviewApp.swift:58`).
>
> **Extend `HostSidebarModel`/`PreviewSelectionVisuals` and `makeDocument` — don't re-parse glTF
> or rebuild selection.**
>
> **Test fixtures:** the repo ships only `scripts/testdata/cube/cube.gltf` (1 node / 1 mesh /
> 1 material, **no** cameras / lights / animations / skins / morphs, centered at origin) and
> `scripts/tiny.glb`. Packs that need lights, cameras, animations, skins, morphs, an off-center
> origin, or specific extensions **must fetch a Khronos sample** (e.g. `BoxAnimated`,
> `RiggedSimple`, a `KHR_lights_punctual` sample) — cube.gltf alone will not exercise them.
> Each "Test now" below names the fixture it needs.

## macOS API quick-reference (confirmed)

- **Orthographic camera:** `OrthographicCameraComponent` (`near/far/scale/scaleDirection`).
  Already used for glTF file cameras (`PreviewCamera.applyFileView`, `RealityKitConvert`).
- **Perspective + FOV:** `PerspectiveCameraComponent(near:far:fieldOfViewInDegrees:…)`.
  `ProjectiveTransformCameraComponent` exists for custom matrices.
- **IBL exposure:** `ImageBasedLightComponent.intensityExponent` (macOS 15+; intensity ×2^exp).
  Env rotation has **no dedicated property** — rotate the light entity, but note the code sets
  `inheritsRotation = false` (pins it), so that must be reworked for a rotation control.
- **Wireframe:** `PhysicallyBasedMaterial.triangleFillMode = .lines` (already how `.wire` works).
- **Backface / double-sided:** material `faceCulling` (`.none` = show backfaces). Already set
  per-material at import (`isDoubleSided ? .none : .back`); a runtime toggle just flips it.
- **Debug channels:** `ModelDebugOptionsComponent(visualizationMode:)` — code already uses many
  (`PreviewDebugMode.swift` switch). ⚠ `.lightingDiffuse`/`.lightingSpecular` are cited as
  "unused-but-available" but **were not verified against the current macOS SDK** — confirm the
  enum cases exist before relying on them. There is **no** built-in vertex-color visualization
  mode (see P9).
- **Window chrome:** `.windowStyle(.hiddenTitleBar)` (macOS 11+) gives the transparent-titlebar /
  no-title look. `glassEffect` / `GlassEffectContainer` / `Settings {}` / `.commands` are already
  used in the app (macOS 26 Liquid Glass).

---

## A. View controls (feed `ViewportController`)

### P1 — Center toggle + world-origin gizmo · NEW
- **Goal:** stop force-centering; reveal authored origin.
- **Now (verified):** `PreviewCamera.makeTurntable` always does `entity.position -= centerInPivot`
  (`PreviewCamera.swift:35-36`); no skip flag. `PreviewFloor` (name `"previewFloor"`) is
  `assembled.pivot.addChild(floor)` (`PreviewScene.swift:137`) — parented under the pivot, so it
  sits at the visual center, *not* the authored world origin.
- **Build:** a `center: Bool = true` param on `makeTurntable`; when false, skip the subtraction so
  the model keeps its authored offset. Add a **separate** world-origin axis entity added to the
  **pivot** at local `-centerInPivot` (i.e. at true (0,0,0)), *not* the floor.
```swift
static func makeTurntable(for entity: Entity, center: Bool = true) -> (…) {
    let centerInPivot = entity.convert(position: localBounds.center, to: pivot)
    if center { entity.position -= centerInPivot }   // else: leave authored offset
    // world-origin gizmo lives at true origin in pivot space:
    if !center { pivot.addChild(makeAxisGizmo(at: -centerInPivot)) }
}
```
- **Gotcha:** `makeTurntable` runs in `RealityView { … }` `make` (`PreviewScene.swift:128`). Adding
  the gizmo there is fine (entity setup), but do **not** write `@State`/`PreviewInteraction`
  from `make`/`update` — wrap any state write in `Task { @MainActor in … }` (AGENTS.md pitfall 1).
  Give the gizmo a helper name and add it to `PreviewFloor.isHelperName` / `modelBounds`'
  skip-list so Fit framing ignores it (else it pushes the camera out).
- **Test now:** temp View-menu toggle. cube.gltf is centered at origin — **use an off-center
  fixture** (translate the cube node, or a Khronos sample with authored offset); gizmo pins at
  (0,0,0) while the model sits off to the side. Depended on by P4.

### P2 — Perspective ↔ orthographic · REUSE
- **Now (verified):** preview/fit camera is `PerspectiveCameraComponent` (`makeFrontThreeQuarter`
  builds `PerspectiveCamera()` at `:239`; `applyFit` reads it at `:62`). **Ortho already
  implemented for file cameras** — `applyFileView` builds `OrthographicCameraComponent`
  (`:265-274`); `restoreFitPerspective` (`:290`) swaps back to perspective.
- **Build:** on toggle, put an `OrthographicCameraComponent` on the *preview* camera entity,
  keeping the same eye/orientation. `scale` = vertical world-height that fills the view — derive
  from `bounds` (roughly the projected half-height used in `fitDistance`, ×2×padding).
```swift
var ortho = OrthographicCameraComponent()
ortho.scale = (bounds.max.y - bounds.min.y) * PreviewCamera.previewFitPadding // refine w/ aspect
camera.components.remove(PerspectiveCameraComponent.self)
camera.components.set(ortho)                 // toggle off → restoreFitPerspective(on: camera)
```
- **Gotcha:** `scale` is a fixed world height, so it does **not** re-fit on window resize the way
  perspective distance does — recompute `scale` on Fit and on viewport change. Toggling while a
  file camera is active: `applyFileView` already owns projection there; gate the preview toggle to
  `useSystemOrbit` (`PreviewScene.swift:110`).
- **Test now:** temp View-menu toggle on cube.gltf; parallel edges stay parallel (no foreshortening).

### P3 — Camera presets (front/back/L/R/top/bottom/iso) · NEW (small)
- **⚠ Correction:** there is **no** `cameraPosition(yaw:pitch:)`. The real function is
  `cameraPosition(minBound:maxBound:padding:aspect:)` (`:175`); it reads yaw/pitch from the
  **private constants** `yawDegrees=35`/`pitchDegrees=18` (`:7-8`) and internally overrides yaw
  for thin decals. It is **not** parameterized by angle — you cannot "wrap" it for presets as-is.
- **Build:** refactor `cameraPosition` (and the `makeFrontThreeQuarter` caller) to take
  `yaw`/`pitch` params (default to the current constants), then add 7 preset angle pairs +
  `applyFit`. Keep the thin-axis override behind a flag so presets aren't hijacked.
```swift
static func cameraPosition(minBound:…, yaw: Float = yawDegrees, pitch: Float = pitchDegrees, …)
enum CameraPreset { case front, back, left, right, top, bottom, iso }  // yaw/pitch table
// apply: makeFrontThreeQuarter(…, yaw:preset.yaw, pitch:preset.pitch) then applyFit(to:camera,…)
```
- **Gotcha:** top/bottom look along world +Y — `applyView` (`:305`) explicitly avoids
  `look(at:from:)` because it traps when the view axis ‖ world up; reuse `applyView`, don't
  reintroduce `look`.
- **Test now:** temp menu of 7 on cube.gltf; each reframes and fills the viewport (top shows the
  cube's top face square-on).

### P4 — Reset view · NEW (small)
- **Now:** Fit exists (`applyFit`); Shift-drag pans camera **and** pivot (AGENTS.md pitfall 4),
  auto-rotate yaws a spin child, orbit is RealityKit-managed.
- **Build:** compose `applyFit(to:camera, bounds:, orbitFocus: pivot)` (re-centers the pivot to
  `.zero`, `PreviewCamera.swift:53`) + reset `frame.autoRotateYaw = 0` + restore center flag (P1).
```swift
func resetView() {
    frame.pivot?.setPosition(.zero, relativeTo: nil)   // undo Shift-pan on the pivot
    frame.autoRotateYaw = 0
    PreviewCamera.applyFit(to: camera, bounds: frame.bounds, aspect: aspect(of: viewport),
                           orbitFocus: frame.pivot)
}
```
- **Gotcha:** the orbit control also holds camera state; posing the camera entity re-seeds it, but
  verify orbit doesn't snap back on the next drag. Don't mutate `@State` from `update` — call this
  from a menu action / `Task { @MainActor }`.
- **Test now:** pan + rotate + zoom → temp Reset → returns to the opening front-3/4 fit. Depends on P1.

### P5 — Lighting controls · mixed (integrate `AppLook`/`PreviewLighting`)
- **Now (verified):** IBL via `ImageBasedLightComponent(source:.single(resource), intensityExponent:)`
  (`PreviewLighting.swift:120`); `inheritsRotation = false` at `:121` pins the IBL to world. The
  exponent flows in as `PreviewScene.studioIBLExponent` → `applyLook(…, intensityExponent:)` (`:45`).
  `studioIBLExponent(punctualLightCount:)` returns `-2` (0.25×) when the file has punctual lights
  (`PreviewEmissive.swift:59`). Env catalog + custom HDR import exist (`AppLook`/`AppLookStore`).
- **Build:** (a) **exposure** — thread a session `intensityExponent` down to `applyLook` (add ±EV
  to the `studioIBLExponent` the scene already passes) · **REUSE**;
  (b) **file-lights vs studio** — the `-2` auto-dim is computed once; make it an explicit toggle by
  overriding the `studioIBLExponent` the scene passes (0 = studio full, `-2` = dim for file lights) ·
  **REUSE**;
  (c) **env rotation** — **NEW.** `applyLook` **rebuilds** the IBL entity on every call and sets
  `inheritsRotation = false`, so a rotation must be re-applied after each rebuild; either set
  `ibl.orientation` (and drop the `inheritsRotation=false` pin) or store a session yaw applied in
  `makeIBLEntity`.
```swift
// makeIBLEntity(…): light.inheritsRotation = true; ibl.orientation = simd_quatf(angle: yaw, axis: [0,1,0])
```
- **Gotcha:** don't block first paint on IBL (AGENTS.md pitfall 3) — `applyLook` already falls back
  to key+fill while the HDR loads; keep exposure/rotation changes going through `applyLook` so the
  fallback path still works. Rebuilding the IBL also re-runs `removeReceivers`/`applyReceivers` — keep
  that ordering.
- **Integrate**, don't rebuild, the `AppLookStore` environment picker.
- **Test now:** temp exposure slider (model brightens/darkens) + file-vs-studio toggle. File-vs-studio
  needs a `KHR_lights_punctual` fixture (cube.gltf has no lights); rotation later.

### P6 — Backface / double-sided toggle · REUSE
- **Now:** `faceCulling` set at import (`RealityKitConvert+Material.swift:102`,
  `isDoubleSided ? .none : .back`); fixed, no runtime toggle. Wireframe already works via
  `triangleFillMode = .lines`.
- **Build:** runtime toggle that flips `faceCulling` to `.none` across materials (reuse the
  `DebugMaterialStore` snapshot/restore pattern).
- **Test now:** temp toggle on a model with a flipped face.

### P7 — Orientation gizmo (corner axes) · NEW
- **Build:** small overlay reflecting camera orientation. No existing gizmo/nav-cube.
- **Test now:** overlay in the old UI corner; orbit and confirm it tracks.

### P8 — Field-of-view control · NEW (small, optional)
- **API:** `PerspectiveCameraComponent.fieldOfViewInDegrees` (currently fixed at 35).
- **Test now:** temp slider. Nice-to-have alongside P2/P3.

### P9 — Extra debug channels · NEW (small)
- **Add:** `.lightingDiffuse` / `.lightingSpecular` (available, unused) and **vertex colors**
  (`PreviewStats.hasVertexColors` already detected — needs a viz mode).
- **Test now:** extend the existing debug-mode cycle.

## B. Introspection (feed `SceneModel` / `Availability`)

> **Trust the headline, not this older §B copy.** On `main`, `GLTFSessionDocument` is slim
> (scenes / nodes without TRS or mesh/light/skin / cameras / animations). Most of §B is
> *extend `makeDocument` + add fields*, then surface. P10/P11/P15/clips are the real surface-only bits.

### P10 — Dimensions W×H×D · DONE (surface it)
- **Now:** bounds computed (`PreviewCamera.modelBounds`); extent is logged in `ContentView.swift:188`
  but not surfaced. **Build:** a `dimensions` accessor + readout.

### P11 — Stats expansion · mostly DONE
- **Now (`PreviewStats`):** tri/vertex/material/texture counts, `fileSizeBytes`, `hasVertexColors`,
  `isRigged`, `morphGeometryCount`. **Missing:** texture **max resolution** (needs image decode) —
  the only NEW bit. Also `overlayFacts` omits `animationCount` (one-line fix).

### P12 — Typed node tree · REUSE / extend `makeDocument`
- **Now:** nodes are `index`/`name`/`children`/`cameraIndex?` only. `GLTFNodeLookup` maps node→entity.
- **Build:** persist TRS + `meshIndex`/`lightIndex`/`skinIndex` + infer kind (empty = all nil).

### P13 — Lights enumerated · NEW (persist, then surface)
- **Now:** no `document.lights`. Data is on `GLTFAsset` at convert time.
- **Build:** add `Light{type,color,intensity,range?,innerCone?,outerCone?}` in `makeDocument`.

### P14 — Materials + map presence · NEW (persist, then surface)
- **Now:** no `document.materials`. Channel presence is a **private** `Channels` struct;
  public API is `PreviewDebugMode.available(from:)`.
- **Build:** persist materials + map-presence bools; one canonical source with the debug flags.

### P15 — Available debug channels · DONE (consume it)
- **Now:** `PreviewDebugMode.available(from json:)` filters the cycle. There is no public
  `PreviewDebugMode.Channels`.

### P16 — Skin / morph · mixed
- **Now:** `isRigged` (Bool) + `morphGeometryCount` (mesh count). Morph weights set at load +
  driven by animation via `BlendShapeWeightsComponent`, but **not user-adjustable**.
- **Build:** runtime morph sliders (write `BlendShapeWeightsComponent` weights) · NEW; skeleton
  overlay · NEW. No per-joint/per-target enumeration exists yet.

### (Animations) — DONE (expose)
- `PreviewClip` (name/duration) exists but is **private to `PreviewScene`**; `document.Animation`
  has name/duration. Expose a shared clips model.

## C. Inspector honesty

### P17 — glTF validation · NEW
- **Now:** loader is **GLTFKit2** (no validation); malformed files tolerated heuristically. No
  validator anywhere.
- **Build:** integrate the Khronos glTF-Validator; map to a warnings list. Headline feature.
- **Test now:** unit test on an invalid fixture; temp badge.

### P18 — Pipeline report · NEW
- **Now:** transforms run **silently, unrecorded.** Confirmed transforms to record:
  dequantize (`KHR_mesh_quantization`), webp→png (`EXT_texture_webp`), GPU-instance expand
  (`EXT_mesh_gpu_instancing`), spec-gloss→metal-rough (+ texture baking), emissive-drop
  (`PreviewEmissive.shouldIgnore` / `fileLooksBaked`), IBL dim (`studioIBLExponent = -2`), Draco
  (`GLBDracoDecompressor`). `needsPrepare`/`needsConversion` gate them.
- **Build:** record a per-file flag set as these run; expose as `pipelineReport`.
- **Test now:** unit test asserts flags on known fixtures.

### P19 — Screenshot action · REUSE + NEW wiring
- **Now:** `StillRenderer` renders **offscreen from an entity tree** (own `RealityRenderer`) — it
  is wired to `ThumbnailExtension`, **cannot grab the live `RealityView`.**
- **Build:** an action that re-renders offscreen at the **current camera pose** (feed the live
  camera transform into `StillRenderer`) and saves via a save panel. Note it's a re-render, not a
  live framebuffer capture.
- **Test now:** temp menu item writes a PNG matching the current view.

## D. Selection / visibility / state

> Selection + per-node **hide** are built. Isolate/solo is **not** (no `soloRoot` on `main`).
> P30 is adopt; P31 must build isolate; P32 is a view on document fields from P12–P14.

### P30 — Selection → canvas highlight · DONE
- **Now:** `selectNode` toggles `selectedNodeIndex`; `PreviewSelectionVisuals` dims non-selected
  (`OpacityComponent 0.28`), draws a yellow AABB wirebox, adds `HoverEffectComponent`. The list row
  gets an accent bg. New UI just adopts this.

### P31 — Per-node visibility + isolate · mixed
- **Now:** `hide: Set<Int>` + eye + `showAll()` exist. **No** `soloRoot`/`soloHides`. Option-click
  eye currently expands/collapses descendants, not isolate.
- **Build:** add isolate/solo logic; wire a modifier that does not steal expand/collapse.

### P32 — Selection detail · build the view (after P12–P14)
- **Now:** `selectedNodeIndex` exists; node/light/material fields land in P12–P14.
- **Build:** detail view from those fields. Show only what the node kind has.

### P33 — Single-source session state · DONE on `main`
- **Now:** storage is source of truth (`PreviewScene.swift`); `autoRotate` is registered
  (`GLBPreviewApp.swift`). Do not redo P33. P34 (per-window vs sticky) is the remaining call.

### P34 — Multi-window independence · DECISION
- **Now:** cross-window bleed **confirmed** — host controls share `UserDefaults.standard`;
  toggling in one window fires the other's `onChange`. Decide sticky vs per-window (DESIGN.md).
- **If per-window:** seed session from defaults at open, never write back (drops the `isHost`
  persistence branch).
- **Test now:** two windows, toggle in one, watch the other.

## E. New capabilities the audit surfaced (optional)

### P40 — Material variants (`KHR_materials_variants`) · NEW (optional)
- **Not handled** anywhere (no `variant` in code). If GLTFKit2 exposes variant mappings, a variant
  switcher (e.g. shoe colorways) is a strong inspector feature. Verify loader support first.

### P41 — Extensions-used panel · NEW (small)
- The prepare pipeline knows every extension (clearcoat, emissive_strength, ior, specular, unlit,
  mesh_quantization, texture_transform, gpu_instancing, texture_webp, meshopt, Draco) but never
  surfaces them. A "what's in this file" list pairs with P18.

---

## Do-first shortlist (biggest value, no deps)
**P17** validation · **P18** pipeline report · **P1** center+gizmo · **P2** ortho (mostly reuse) ·
**P5a/b** exposure + file-vs-studio (cheap) · **P7** orientation gizmo.
Selection/visibility (P30–P32) is largely done — audit, then adopt, before writing new code.
Resolve **P33/P34** (state) before the second new control lands.
