# Engine Feature Packs — codebase work for the new UI

Backs [DESIGN.md](DESIGN.md); feeds the seam in [UI-BUILD.md](UI-BUILD.md) §0.
**Each pack is independent and testable in the CURRENT UI now** — add a throwaway control
(menu item, toggle, print, or test) to prove it, then bind to the seam later.

> **Verified 2026-08-21** against branch `feature/scene-interaction-controls` (three code
> passes + RealityKit/SwiftUI docs via Context7). Status legend:
> **DONE** = exists, only needs surfacing · **REUSE** = plumbing exists, thin wrapper ·
> **NEW** = net-new · **DECISION** = needs a call first.
> The headline correction from the audit: the codebase already has a full parsed scene model
> (`GLTFSessionDocument`), a working outliner with selection/visibility/solo
> (`HostSidebarModel` + `PreviewSelectionVisuals`), and channel-presence detection
> (`PreviewDebugMode.Channels`). **Extend these — do not re-parse glTF or rebuild selection.**

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
- **Debug channels:** `ModelDebugOptionsComponent(visualizationMode:)` — code already uses many;
  unused-but-available: `.lightingDiffuse`, `.lightingSpecular`.
- **Window chrome:** `.windowStyle(.hiddenTitleBar)` (macOS 11+) gives the transparent-titlebar /
  no-title look. `glassEffect` / `GlassEffectContainer` / `Settings {}` / `.commands` are already
  used in the app (macOS 26 Liquid Glass).

---

## A. View controls (feed `ViewportController`)

### P1 — Center toggle + world-origin gizmo · NEW
- **Goal:** stop force-centering; reveal authored origin.
- **Now:** `PreviewCamera.makeTurntable` always does `entity.position -= centerInPivot`
  (`PreviewCamera.swift:35-36`); no skip flag. `PreviewFloor` is a polar grid **parented under
  the pivot** (follows the model) — *not* a world-origin indicator.
- **Build:** a `center` flag on `makeTurntable` to skip the subtraction; a **separate**
  world-origin XYZ axis entity (the floor won't do — it moves with the pivot).
- **Test now:** temp View-menu toggle; open an off-center model — gizmo at (0,0,0), model offset.

### P2 — Perspective ↔ orthographic · REUSE
- **Now:** preview/fit camera is `PerspectiveCameraComponent` (`makeFrontThreeQuarter`
  `:239`, `applyFit` `:62`). **Ortho already implemented for file cameras**
  (`applyFileView:265-274` builds `OrthographicCameraComponent`; `restoreFitPerspective:290`
  swaps back).
- **Build:** apply the existing ortho component to the *preview* camera; recompute `scale`
  from bounds (mirror `applyFit`'s framing). Small.
- **Test now:** temp toggle; verify no foreshortening.

### P3 — Camera presets (front/back/L/R/top/bottom/iso) · NEW (small)
- **Now:** only one canned pose (front-three-quarter, yaw 35°/pitch 18°). `cameraPosition(yaw:pitch:)`
  (`:175`) is parameterized and reusable.
- **Build:** 7 wrappers over `cameraPosition` + `applyFit`.
- **Test now:** temp menu of 7; verify each frames the model.

### P4 — Reset view · NEW (small)
- **Build:** compose Fit + center-on (P1) + clear Shift-pan offset.
- **Test now:** pan/rotate → temp Reset → returns. Depends on P1.

### P5 — Lighting controls · mixed (integrate `AppLook`/`PreviewLighting`)
- **Now:** IBL via `ImageBasedLightComponent(intensityExponent:)` (`PreviewLighting.swift:120`);
  `studioIBLExponent(punctualLightCount:)` returns `-2` (0.25×) when the file has punctual lights
  (`PreviewEmissive.swift:59`). Env catalog + custom HDR import already exist
  (`AppLook`/`AppLookStore`, `PreviewSettingsPane`). `inheritsRotation = false` pins the IBL.
- **Build:** (a) **exposure** — surface `intensityExponent` as a control · **DONE-ish**;
  (b) **file-lights vs studio** — make the auto-dim an explicit toggle · **REUSE**;
  (c) **env rotation** — **NEW**, and rework the `inheritsRotation=false` pin.
- **Integrate**, don't rebuild, the `AppLookStore` environment picker.
- **Test now:** temp exposure slider + file-vs-studio toggle (both cheap); rotation later.

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

> **`GLTFSessionDocument` is already a full parsed model** — scenes, nodes (TRS + mesh/camera/
> light indices + children), meshes (counts), materials (factors + per-map Bools), lights
> (type/color/intensity/cone), cameras (persp/ortho), animations (name/duration). Most of §B is
> *surfacing*, not building.

### P10 — Dimensions W×H×D · DONE (surface it)
- **Now:** bounds computed (`PreviewCamera.modelBounds`); extent is logged in `ContentView.swift:188`
  but not surfaced. **Build:** a `dimensions` accessor + readout.

### P11 — Stats expansion · mostly DONE
- **Now (`PreviewStats`):** tri/vertex/material/texture counts, `fileSizeBytes`, `hasVertexColors`,
  `isRigged`, `morphGeometryCount`. **Missing:** texture **max resolution** (needs image decode) —
  the only NEW bit. Also `overlayFacts` omits `animationCount` (one-line fix).

### P12 — Typed node tree · REUSE
- **Now:** `document.nodes` have `meshIndex?/cameraIndex?/lightIndex?` + TRS + children; **no
  explicit kind enum, no `skinIndex`**. `GLTFNodeLookup.entity(nodeIndex:in:)` maps node→entity.
- **Build:** a small tree model that infers kind from which optional is set (empty = all nil).

### P13 — Lights enumerated · DONE (surface it)
- **Now:** `document.lights` = `Light{type,color,intensity,range?,innerCone?,outerCone?}` — point/
  spot/directional already distinguished. Just render the Lights section.

### P14 — Materials + map presence · DONE (build the list UI)
- **Now:** presence known in **two** places — `document.Material.has{BaseColor,MetallicRoughness,
  Normal,Occlusion,Emissive}Texture` Bools, and `PreviewDebugMode.Channels` (adds clearcoat/
  specular/tangent). **Build:** the materials-list UI; **consolidate** the two sources.

### P15 — Available debug channels · DONE (consume it)
- **Now:** `PreviewDebugMode.Channels.available(from:)` already filters the cycle to channels
  present in the model. The new view-mode menu just reads this.

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

> **Selection + visibility are already substantially built** in `HostSidebarModel` +
> `PreviewSelectionVisuals`. These packs are mostly *surfacing/wiring*, not building.

### P30 — Selection → canvas highlight · DONE
- **Now:** `selectNode` toggles `selectedNodeIndex`; `PreviewSelectionVisuals` dims non-selected
  (`OpacityComponent 0.28`), draws a yellow AABB wirebox, adds `HoverEffectComponent`. The list row
  gets an accent bg. New UI just adopts this.

### P31 — Per-node visibility + isolate · mixed
- **Now:** per-node `hide: Set<Int>` with eye buttons (`HostOutlinerView` / `applyVisibility`) —
  **DONE.** Isolate/solo **logic** exists (`soloRoot`, `soloHides`, `showAll`) but has **no UI
  trigger** on this branch.
- **Build:** wire an isolate control (Option-click eye) to the existing solo logic · small.

### P32 — Selection detail · DONE (build the view)
- **Now:** `selectedNodeIndex` + `document.nodes[i]` (TRS, mesh/camera/light index) + `materials`
  give all inspector data. **Build:** the detail view; no new engine data needed.

### P33 — Single-source session state · NEW (⚠ branch note)
- **⚠ On THIS branch the OLD mirror pattern is present** (local `@State` + bidirectional `onChange`
  + `onAutoRotateChanged` callback + `applyAutoRotateSetting`). The single-source refactor was done
  on `simplify/autonomous-reduction`, **not here** — either merge it or redo it. Also `autoRotate`
  is **not** registered in `UserDefaults.register` (default only lives in `= true` literals).
- **Build:** storage = source of truth; render computes the effective value; extend to the new
  controls (view-mode/lighting/camera/ortho) + a "Set as default" affordance. Do after ≥2 new
  controls exist.

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
