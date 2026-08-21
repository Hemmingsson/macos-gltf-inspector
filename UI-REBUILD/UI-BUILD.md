# UI Build — new interface, built in isolation

Target design: [DESIGN.md](DESIGN.md). Engine work that backs it:
[ENGINE-FEATURE-PACKS.md](ENGINE-FEATURE-PACKS.md).

**Strategy:** build the new UI as a standalone module driven by mock data, perfect it, then
inject the real engine behind the same protocols. The UI never imports the engine — it
depends only on "the seam" (§0). The shell app injects mocks; the real app injects
engine-backed conformances. **At cutover there is no UI rewrite, only a different
implementation injected.**

> **Re-verified 2026-08-21 against `main`.** Engine adapters stay thin — extend
> `makeDocument` / `HostSidebarModel` / `PreviewSelectionVisuals`; do not re-parse glTF or
> rebuild selection. `GLTFSessionDocument` is **slim** (no lights/materials/TRS). Hide exists;
> isolate does not. `PreviewDebugMode.available(from:)` is the public channel API. Details:
> `ENGINE-FEATURE-PACKS.md` headline. The §0 "gap" table below can lag — trust that headline.

```
        ┌─────────────────────────────┐
        │  PreviewUI  (SwiftUI views)  │   ← perfected once, used by both
        │  depends only on PROTOCOLS   │
        └───────────────┬─────────────┘
        injects mocks ↙   ↘ injects engine
   ┌───────────────┐        ┌──────────────────────┐
   │ PreviewUIShell│        │  GLBPreview (real)   │
   │ (mock data)   │        │  EntityLoader etc.   │
   └───────────────┘        └──────────────────────┘
```

---

## 0. The seam — protocols (do FIRST; the contract both sides target)

A `PreviewUI` package exposing **protocols only**. The mock impls live in the shell; the
engine impls (`ENGINE-FEATURE-PACKS.md`) live in the real app. Lock these signatures early —
they let the UI track and the engine track run fully in parallel.

| Protocol | Role | Key members |
|---|---|---|
| `SceneModel` | read-only file introspection | `scenes`, `nodeTree` (typed: mesh/camera/light/empty/skin), `cameras`, `lights`, `materials` (+maps present), `animations` (+durations), `skins`, `morphs`, `stats`, `dimensions`, `validation`, `pipelineReport` |
| `Availability` | drives "show only what the model has" | `hasAnimations`, `hasLights`, `hasCameras`, `isMultiScene`, `hasSkin`, `hasMorphs`, `availableDebugChannels` |
| `ViewportController` | what pills / menu call | `setBackdrop`, `setFloor`, `setAutoRotate`, `setCenter`, `setViewMode`, `setProjection`, `setLighting`, `fit()`, `reset()`, `applyCameraPreset(_)`, `screenshot()` |
| `SelectionModel` | sidebar ↔ canvas | `selected`, `select(_)`, `detail`, `setVisible(_,_)`, `isolate(_)` |
| `SettingsStore` | defaults + per-window session | `default(for:)`, `sessionValue(for:)`, `setSession(_)`, `promoteToDefault(_)` |

> `SettingsStore` defaults = the App-default job; `sessionValue` = the This-window job. The
> render reads the effective value; the canvas never writes defaults (DESIGN.md three-job rule).

### The engine impls are thin adapters (what already exists)

| Protocol | Backed today by | Gap to fill |
|---|---|---|
| `SceneModel` | slim `GLTFSessionDocument` + `PreviewStats` | persist node kind/TRS/mesh/light/skin, lights, materials (P12–P14); dimensions; max-res; `validation` (P17); `pipelineReport` (P18) |
| `Availability` | derive from document + `PreviewStats` + `PreviewDebugMode.available(from:)` | compute the booleans |
| `ViewportController` | backdrop/floor/auto-rotate/debug-mode/Fit | center (P1) · projection (P2) · presets (P3) · reset (P4) · lighting (P5) · screenshot (P19) |
| `SelectionModel` | `HostSidebarModel` (`selectedNodeIndex`, `hide`) + `PreviewSelectionVisuals` | isolate (P31, not built yet) · detail view (P32) |
| `SettingsStore` | `@AppStorage`; P33 single-source **already on `main`** | P34 per-window vs sticky |

> Existing seams to reuse: `PreviewOverlay` (`Shared/PreviewChrome.swift`) already bridges scene
> ↔ sidebar (`selectedCameraIndex`, `document`); `GLTFNodeLookup` maps node index → entity.

---

## 1. Secondary shell app (`PreviewUIShell`)

A tiny macOS target that hosts `PreviewUI` with mock conformances — where we iterate to perfection.

- [ ] `PreviewUI` package + `PreviewUIShell` target in `project.yml`.
- [ ] Mocks: `MockSceneModel`, `MockViewportController`, `MockSelection`, `MockSettings`.
- [ ] **Fixture switcher** in the shell (menu/segmented) to swap the §2 mocks — how we verify
      adaptive UI.
- [ ] Placeholder canvas: a RealityKit primitive (cube/sphere) or static gradient. The chrome
      is the point, not the 3D content.
- [ ] Build the §1a components against mocks; wire interactions to session state.
- [ ] Polish: light/dark, Reduced Motion, Increase Contrast, keyboard focus, glass, spacing.

### 1a. Components (in `PreviewUI`)

- [ ] Window frame — `.windowStyle(.hiddenTitleBar)` (macOS 11+) for the no-title / transparent
      titlebar; traffic-light inset, file name in sidebar. `glassEffect` / `GlassEffectContainer`
      are already in the app (`PreviewChromeBar`) — reuse, don't re-add.
- [ ] Left sidebar — sectioned outliner; **sections render only when populated**; typed tinted
      icons; hover eye + isolate.
- [ ] Three toolbar pills — **Stage** (swatches · floor) · **Look** (view-mode menu · lighting
      popover) · **Camera** (auto-rotate · center · persp↔ortho · Fit · presets).
- [ ] Backdrop swatches · view-mode dropdown (full names, **only available channels**) ·
      lighting popover (exposure / env rotation / file-vs-studio).
- [ ] Right inspector — selected node (transform / geometry / material chips) · file stats ·
      validation badge (expands) · "what our pipeline did" list · actions on the header row.
- [ ] Canvas overlays — orientation gizmo · dimensions readout · origin gizmo (center-off) ·
      playback bar (**only when `hasAnimations`**).
- [ ] Empty / loading / failed states.
- [ ] macOS **View menu** mirroring every pill control, with shortcuts (keyboard twin).

## 2. Mock fixture matrix (proves the adaptive UI)

| Fixture | Exercises |
|---|---|
| `plainMesh` | near-empty UI: no anim / lights / cameras / scene switcher |
| `riggedAnimated` | playback bar, Animations section, skeleton / morph controls |
| `multiScene` | Scene switcher visible |
| `withLights` | Lights section, file-vs-studio lighting |
| `withCameras` | Cameras section |
| `missingChannels` | view-mode hides absent channels; material chips omit absent maps |
| `invalidFile` | validation warnings + pipeline report |

## 3. Cutover (when the UI is perfect)

1. Engine track (`ENGINE-FEATURE-PACKS.md`) has landed the capabilities; write the
   engine-backed conformances (`EngineSceneModel`, `EngineViewportController`, …) adapting
   `EntityLoader` / `PreviewScene` / `PreviewCamera` to the §0 protocols.
2. Host `PreviewUI` in `GLBPreview`, inject the engine conformances, delete old chrome.
3. Verify with **real windows** per AGENTS.md (one open/ready, no "Modifying state"), across
   the §2 matrix on real files.
4. Bring Quick Look + thumbnail extensions onto the shared components where they apply.

## Parallelization

- **Track A (this doc):** §0 → §1 → §2. No engine dependency; fast iteration.
- **Track B:** `ENGINE-FEATURE-PACKS.md`, each pack independent and testable in the old UI now.
- **Join:** §3. Both tracks target §0, so they meet cleanly.
