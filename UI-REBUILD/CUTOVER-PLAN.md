# Cutover Plan — new UI into the real app, cleanly

How we take the perfected `PreviewUI` (built in isolation in the `PreviewUIShell`) and land it
in `GLBPreview`, delete the old chrome, and keep the tree tidy and building at every step.

Companion docs: [DESIGN.md](DESIGN.md) · [UI-BUILD.md](UI-BUILD.md) (strategy/seam) ·
[UI-IMPLEMENTATION-PLAN.md](UI-IMPLEMENTATION-PLAN.md) (how the shell was sliced) ·
[ENGINE-FEATURE-PACKS.md](ENGINE-FEATURE-PACKS.md) (engine packs).

This plan is in **two parts**, as requested:
- **Part A — Fixes & cleanup to do *before* the cutover** (some in `main`, some in the UI worktree).
- **Part B — The cutover itself** (inject the UI into the real app, delete the old, verify).

---

## 0. Where we actually are (re-verified 2026-08-22, post A0)

Read this first — branch reality has moved; treat older "untracked UI" notes as historical.

1. **UI is committed on `ui-rebuild` (A0 done).** Tip `ab16854` — `PreviewUI/` + `PreviewUIShell/`
   are in history (`e7f2e69`…`ab16854`). **Still not safe for cutover:** `ui-rebuild` does **not**
   contain Track B. It is **behind `main`** by (at least) `a7e9199` (engine packs) + two Peekaboo
   doc commits + fixture share (`main` tip `56a4077`). Next gate: **merge/rebase `main` into `ui-rebuild`**, resolve
   `project.yml` + doc drift, prove both schemes build. Push if not already remote.

2. **Track B engine packs are on `main` (not equal to `engine-features` tip).** `engine-features`
   is still parked at `a7e9199`; `main` has moved past it. Pack code tagged "DONE (features)" lives
   on `main`. The `engine-features` branch / `.worktrees/features` remain redundant cleanup (A5/B7).

3. **The shell is done and green.** All 8 slices are implemented; `PreviewUIShell` builds, and
   carries **no TODO/FIXME/`fatalError`** (mocks may `preconditionFailure` on type mismatch — fine).
   UI proof is Peekaboo on a live window (no headless `--snapshot` / flatten-glass harness). The
   seam is **5 protocols** (`SceneModel`, `ViewportController`, `SelectionModel`, `SettingsStore`,
   `Availability`) + value types — **no `AnimationPlaybackController` yet** (A2).

**Two stale docs to correct (they will mislead whoever executes this):**
- `ENGINE-FEATURE-PACKS.md` on **`main`** still says P17 is *"still absent — cherry-pick…"*
  **False.** `Shared/GLTFValidator.swift`, `Vendor/gltf-validator/`, fixtures, tests, and host
  wiring are on `main`. The `ui-rebuild` copy of this doc also drifts — reconcile to **main's tree
  + A1 corrections**, not an older worktree draft.
- Whole-doc framing *"Status on engine-features"* is obsolete: packs shipped on `main`.

---

# Part A — Fixes & cleanup before the cutover

Goal: eliminate risk, correct the record, close the real seam/engine gaps, and make the product
decisions — so Part B is pure, low-surprise adapter work.

### A0. De-risk: get the UI work into git *(mostly done — finish the merge)*

Work in `.worktrees/ui` on `ui-rebuild`.

1. ~~**Commit the UI**~~ — **done** (`e7f2e69`…`ab16854`).
2. **Merge or rebase `main` (`1c3018a`+) into `ui-rebuild`** so the branch is *main + UI*. Expect
   `project.yml` conflict (shell adds a 4th target + scheme; take both sides) and doc conflicts
   under `UI-REBUILD/`. After merge, **both** `PreviewUIShell` and `GLBPreview` must build; run
   existing tests on the merged tree.
3. **Reconcile the doc drift.** Prefer **main's** `ENGINE-FEATURE-PACKS.md` / `DESIGN.md` /
   `UI-BUILD.md` as the base (they reflect shipped packs), then fold A1 corrections + keep
   worktree-only docs (`PROMPT-UI.md`, `UI-IMPLEMENTATION-PLAN.md`, this cutover plan). Commit once.
4. Push `ui-rebuild` if the remote is behind. **Then** Part A seam/engine work proceeds on that
   branch.

*Output of A0:* one branch (`ui-rebuild`) = current `main` + `PreviewUI` + `PreviewUIShell`,
building, pushed.

### A1. Correct the stale docs *(5 minutes, high clarity)*
- `ENGINE-FEATURE-PACKS.md`: delete the P17 "still absent / cherry-pick" note; mark P17 present on
  `main`. Replace the "Status on engine-features" header with "Status on `main` (merged)".
- Note the one genuinely-open item that survives: **P34** (per-window vs sticky) — decided in A4.

### A2. Close the seam's own holes *(cheap, mock-only, do while there's no engine risk)*

The shell is complete, but three contract gaps will bite at cutover if left. Fix them in
`PreviewUI`/`PreviewUIShell` now, while everything is still mock-driven and instantly verifiable:

- **Animation playback has no seam.** `Overlays/PlaybackBar.swift` runs a local `@State` clock;
  there is no protocol for the engine to satisfy, even though `PreviewClip`/`PreviewScene` already
  play clips. **Add an `AnimationPlaybackController` protocol** (`@MainActor @Observable`:
  `clips`, `activeClip`, `isPlaying`, `time`, `duration`, `play()/pause()/seek(_)/select(_)`), back
  `PlaybackBar` with it, and give the shell a `MockPlayback`. This is the only *missing* piece of
  contract — decide its shape now, not during the cutover.
- **Screenshot path is a dead no-op in the shell.** `NodeHeader`'s `onScreenshot` threads up to a
  `{}` default; `MockViewport.screenshot()` exists but nothing calls it. Wire `ShellWindow` to call
  `viewport.screenshot()` so the end-to-end path is proven before the engine has to honour it.
- **Multi-scene switching (A4) — do not regress the host.** Today the **real app already
  switches scenes**: `HostSidebarModel.activeSceneIndex` + outliner `Picker` + `ContentView`
  re-convert via `EntityLoader.convertScene`. The PreviewUI seam only *lists* `scenes` /
  `defaultSceneID`; selecting a scene goes through `SelectionModel` as inspector detail, with
  **no** `setScene` / `activeSceneID`. `Availability.isMultiScene` (and `hasCameras` / `hasSkin` /
  `hasMorphs`) are largely unread by production PreviewUI views. **If multi-scene stays in v1
  (recommended — host already ships it), A2 must add active-scene to the seam before B2**, or the
  cutover drops a live feature. If product says listing-only, document that as an intentional
  regression and remove the host Picker path explicitly.

### A3. Close the engine gaps on `main` so the adapter stays thin

Each engine pack is real; the gaps below are what the seam asks for that the document/engine does
**not** yet stamp. Order is by "does the inspector actually need it." Land these on `main` (or the
cutover branch) with the existing test fixtures — every one is testable in the current app today.

**Needed for correctness (do before cutover):**
- **`availableDebugChannels` without re-parsing JSON.** `PreviewDebugMode.available(from:)` needs
  the raw glTF header, and `GLTFSessionDocument` does not keep JSON — **but the gap is thinner than
  "persist on the document."** `EntityLoader.LoadedModel` already carries
  `debugModes: [PreviewDebugMode]` (and `PreviewDebugMode.availableDebugChannels(from:)` exists).
  **Prefer:** keep `debugModes` (or the channel ID list) on the window/load result the adapter
  already sees — same place `ContentView` already threads `model.debugModes` today. Stamping onto
  the document is optional, not required for a thin adapter.
- **Persisted `center` + `projection` settings keys.** Today these are session-only `@State`
  (`sessionCenterModel`, `sessionOrthographic`) with **no `UserDefaults` default**. `SettingsStore.
  default(for:)`/`promoteToDefault` need real keys *if* they stay in the seam key set. Prefer A3b's
  recommendation: keep them session-only and **drop** `.center`/`.projection` from persisted
  defaults rather than inventing Settings rows DESIGN.md does not want.
- **Per-node bound material (inspector honesty).** `SelectionDetail`'s materials are the *file-level
  inventory*, not the node's bound material — the code comment admits the mesh→material bind isn't
  on the document. Left as-is, `NodeDetail.material` shows the wrong material, violating DESIGN.md's
  "inspector honesty." **Stamp mesh→material binding** in `RealityKitConvert.makeDocument`
  (primitive `materialIndex` already exists in mesh convert for RealityKit parts — it never reaches
  `GLTFSessionDocument.Node`).

**Scope decision drives these (A4 "inspector depth"):**
- **Material rich detail.** `GLTFSessionDocument.Material` carries only `name` + `MaterialMapPresence`.
  The seam `MaterialInfo` wants `workflow`, `alphaMode`, `isDoubleSided` (non-optional) + factors +
  texture pixel sizes. `isDoubleSided` is already known at import (`faceCulling`); `workflow`/
  `alphaMode`/factors come straight off the GLTFKit2 material. Stamp the cheap non-optionals now;
  texture pixel sizes are optional (seam allows nil) — defer unless the inspector shows them.
- **Per-node `GeometryInfo`.** `PreviewStats` is file-level only; the seam wants per-node
  tri/vertex/UV/normals/tangents/colors. `NodeDetail.geometry` is optional — **recommend deferring
  exact per-node counts for v1** (chips stay), adding them only if the inspector demands them.

**Structural (design during cutover, but decide the approach now):**
- **Validation is async; the seam snapshot is synchronous.** `GLTFValidationState` is
  `.success/.failed/.skipped`, computed after first paint (nil while pending); the seam exposes
  `validation: ValidationResult` as a plain getter on a `Sendable` snapshot. **Approach:** the real
  `EngineSceneModel` is *re-snapshotted* when validation resolves (the window owner re-emits), and
  `.failed`/`.skipped` map to a synthetic info issue rather than silence. Nail this in B1.

**Minor mapping (fold into B1, no separate work):** `Stats.meshCount` (derive from distinct
`meshIndex`), `Dimensions.authoredOrigin` (from bounds), `PipelineReport` extensions slot (fold
`extensionsUsed` P41 into `entries` or add a field), `LightingSettings` shape (degrees↔radians;
map carefully — see below), selection **toggle-vs-set** (`HostSidebarModel.selectNode`/`isolate`
toggle; seam `select(_)`/`isolate(_)` are set-with-nil-to-clear).

**Lighting mapping (do not hand-wave):** Host session has `exposureEV`, `environmentYaw` (radians),
`dimStudioForFileLights`. Seam `LightingSettings` has `exposure`, `environmentRotationDegrees`,
`usesFileLights`, `usesStudioEnvironment`. Closest mapping: exposure↔EV, yaw degrees↔radians,
`usesFileLights` ↔ file-lights / dim-studio UX (Look pill Studio|File when `hasLights`).
`usesStudioEnvironment` is **not** the same as host `dimStudioForFileLights`, and studio IBL is
**not** "always on": `AppLook.useEnvironmentMap` can turn the environment map off entirely (app
default). Adapter must not invent a second on/off that fights `AppLook`.

### A3b. Settings — bring over ALL three panes, adapt to the new philosophy

The shell's `SettingsStore` models only 5 canvas keys (`autoRotate`, `showFloor`, `center`,
`backdrop`, `projection`). The real app's Settings has **three panes with features the seam
dropped** — bring them ALL over, adapted to the new UI (not lost):

| Pane | Setting (on `main`) | Backing to KEEP | Job in new UI |
|---|---|---|---|
| General | Appearance System/Light/Dark | `SettingsAppearance` + `SettingsKeys.appearance` | **App-wide** (not per-window) |
| General | Set as Default Application (+ current handler) | `NSWorkspace` + glTF `UTType`s | App action |
| Preview | Auto-rotate default | `.autoRotate` ✅ in seam | App default → per-window overlay |
| Preview | Polar floor default | `.showFloor` ✅ in seam | App default → per-window overlay |
| Preview | Background default | `.backdrop` ✅ in seam | App default → per-window overlay |
| Preview | Show toolbar on open | `SettingsKeys.showToolbar` ❌ **missing** | App default (maps to "show canvas pills on open") |
| Preview | **Use environment map** | `AppLook`/`AppLookStore` ❌ **missing** | App default (lighting) |
| Preview | **Environment catalog picker** (Khronos thumbnails) | `KhronosEnvironments` + `EnvironmentCatalogPicker` ❌ **missing** | App default (which IBL) |
| Preview | **Add your own HDR/EXR** (custom import) | `AppLook.supportDirectory` import ❌ **missing** | App default (custom IBL) |
| About | Icon · version/build · GitHub link | `AboutSettingsPane` + `GLBUpdateConfig` | Static; keep as-is |
| (app menu) | Check for Updates | Sparkle `CommandGroup(after: .appInfo)` | Keep |

**The biggest miss is the whole environment/IBL system** (`Shared/AppLook.swift`, `AppLookStore`,
`KhronosEnvironments`, custom HDR/EXR import + thumbnails — it has `AppLookTests`). Re-home it into
the new Preview pane, behaviour unchanged. The seam's `LightingSettings` covers only *per-window*
exposure/rotation/file-vs-studio — the **catalog choice is an app default** and needs a new settings
key plus the picker UI ported.

**Reconcile the two lighting homes (DESIGN.md three-job rule):**
- **App default (Settings):** which environment map (catalog / custom HDR) · use-env-map · appearance ·
  backdrop · floor · auto-rotate · show-pills-on-open · auto-play.
- **This window (Look pill):** exposure · env rotation · file-vs-studio — the live `LightingSettings`.

**Center / projection:** DESIGN.md lists these as *this-window only*, not app defaults. Recommend
dropping `.center`/`.projection` from the persisted default set (keep them session-only with a fixed
initial — center on, perspective) rather than surfacing them in Settings, unless you want a default.

Expand the seam's `SettingKey` set for **real ports** (appearance, showPills←`showToolbar`,
useEnvironmentMap, environmentCatalog, customEnvironmentFile), split by job, and rebuild
`SettingsRootView`'s 3-tab `TabView` (General / Preview / About) hosting the ported panes, driven
by the seam store.

**`autoPlay` is not a port.** There is no `autoPlay` key/pane on `main` or in the shell today —
only DESIGN.md desire. Treat it as an optional greenfield add (A4), not "bring over from Settings."

### A3c. Lock the propagation model — *"if on default, update live; if changed, don't"*

**This is not complex or too complex — it is exactly what the seam already computes, done right.**
`sessionValue(for:)` already returns *"the window's override if it set one, otherwise the app
default."* Your rule falls out of that for free, with **two adjustments** to the shell's current
implementation:

1. **Stop eagerly seeding.** Today `MockSettings.seedSessionFromDefaultsIfNeeded()` copies *all*
   defaults into the window at open — which pins every window and kills live default-tracking. Drop
   it. A window gains an override for a key **only when the user actually changes that control on
   that window** (the pills already call `setSession`). Untouched keys fall through to the default.
2. **Make defaults observable and shared.** Hold app defaults in one app-level `@Observable` store
   (backed by `UserDefaults`, observing `UserDefaults.didChangeNotification`), injected into every
   window — not per-window raw `UserDefaults` reads, which SwiftUI won't re-render on. The Settings
   scene writes that shared store; `ShellDefaultsView`'s throwaway `MockSettings()` instances become
   the one shared store.

Resulting behaviour = your spec, exactly:
- Window **still on the default** backdrop → follows a Settings default change **live**.
- Window where the user **already changed** the backdrop → keeps its own; the Settings change is
  ignored for that window/key.
- **New windows** open on the current default.
- A per-window **"Reset to defaults"** (`clearSession()`) drops overrides and re-tracks defaults.

App-wide settings (appearance) skip the overlay entirely — they apply everywhere immediately.

### A4. Product decisions to confirm *(these gate Part B scope)*

| # | Decision | Status / Recommendation | Why |
|---|---|---|---|
| 1 | **P34: per-window vs sticky settings** | **CONFIRMED — per-window, lazy overlay (A3c)** | Effective-value model: untouched keys track the default live; touched keys stick per window. Matches DESIGN.md and needs only the two A3c adjustments. |
| 2 | **Inspector depth** (material factors / per-node geometry counts) | **Ship map-chips + cheap material non-optionals + honest bound material; defer per-node exact counts** | Honest and calm now (DESIGN.md "show only what the model has"); the heavy per-node accounting is additive later and the seam already allows nil. |
| 3 | **Quick Look scope** | **CONFIRMED — canvas only: orbit + bottom-left info readout + two buttons (backdrop, rotate toggle), reusing main's controls; everything else removed. Done *after* the UI cutover.** | QL is a lightweight preview, not the inspector. No pills cluster, no outliner, no menu. Drives a much-trimmed B5. |
| 4 | **Multi-scene switching in v1?** | **Recommend YES — host already ships it** | Seam must gain active-scene (A2) or B2 regresses `activeSceneIndex` + `convertScene`. Listing-only is a product cut, not free. |
| 5 | **Keep `PreviewUIShell` after cutover?** | **Keep** | Zero-engine-risk design playground + `--proof-outliner`; it never ships. UI regression = Peekaboo on a live window. |
| 6 | **Material variants (P40) in v1?** | **Recommend YES — host already ships it** | `materialVariantNames` / re-convert live on `main`; **absent from PreviewUI seam/outliner**. Easy silent loss at cutover unless A2/B1 add a variants control (or an explicit "drop P40 from UI" decision). |
| 7 | **Host session extras vs seam** | **Must map or explicitly drop** | View menu today also drives `doubleSided`, `showSkeleton`, `fieldOfViewDegrees` (+ lighting). Shell `ViewportController` / shell View menu do **not** cover skeleton / double-sided / FOV. Decide: extend seam + Look/Stage pills, keep FocusedValues bridges beside the seam, or drop from v1 menus. |

### A5. Repo tidy (independent of the cutover)
- Delete stray scratch: `.worktrees/ui/window-*.png` (Peekaboo captures), stray `.DS_Store`s.
- These dirs are already gitignored and are local-only scratch — **leave them**: `.dex/`, `plans/`,
  `.conductor/`, `.cursor/*` (except the tracked skills/agents/hooks), `.worktrees/`.
- **After** the cutover merges (not before): delete the `engine-features` branch and
  `.worktrees/features` (redundant, `== main`), and remove the `ui-rebuild` worktree.

---

# Part B — The cutover: PreviewUI into GLBPreview

Principle from UI-BUILD §3: **the UI code (`PreviewUI/`) does not change** — we only write
engine-backed conformances and inject them. Slice it horizontally like the shell; every phase
builds, runs a real window, and is verifiable on its own. Do it on a branch off `main`.

### B0. Bring `PreviewUI` into the shipping tree
- Merge/rebase the A0 branch so `PreviewUI/` + `PreviewUIShell/` are committed on the cutover branch.
- Keep `PreviewUIShell` as-is (its own target, never ships). App still builds unchanged.
- *Verify:* `xcodebuild -scheme GLBPreview` and `-scheme PreviewUIShell` both build; tests pass.

### B1. Write the engine adapters — `GLBPreview/Engine/` *(the heart of the cutover)*
Five thin conformances over types that already exist on `main`. Each gets a unit test that maps a
real fixture (`scripts/testdata/cube`, `BoxAnimated`, `offcenter`, `invalid`) to the seam types.

| Adapter | Wraps (all on `main`) | Notes |
|---|---|---|
| `EngineSceneModel: SceneModel` | `GLTFSessionDocument` + `PreviewStats` + `ModelDimensions` + `GLTFValidationState` + `PipelineReport` | Consumes A3. Build `nodeTree` from flat `document.nodes` child indices; radians→degrees for fov/cones. Re-snapshot on async validation. |
| `EngineViewportController: ViewportController` | `PreviewScene` session state + `PreviewCamera` + `FocusedPreviewCommands` + still path | Every listed member has a backer; **plus** decide A4-7 for double-sided / skeleton / FOV. `screenshot()` must call the **host** still path (`ContentView.screenshotCurrentCameraPose` → `StillRenderer` + save panel) — that helper is **private on `ContentView` today**, not on `PreviewScene`/`StillRenderer`. Extract or wrap. Map `LightingSettings` per A3 lighting note. |
| `EngineSelectionModel: SelectionModel` | `HostSidebarModel` + `PreviewSelectionVisuals` + `SelectionDetail` | Reconcile toggle-vs-set; `isVisible` from `hide`+`soloHides`; honest `NodeDetail.material` (A3). |
| `EngineSettingsStore: SettingsStore` | `SettingsKeys` (`@AppStorage`) + per-window session | Resolves P34 (per-window). Type-erased `UserDefaults` bridge for the generic `default(for:)`. Also absorb A3c: **stop host ContentView seed-once** the same way the shell drops `seedSessionFromDefaultsIfNeeded`. |
| `Availability` | `DerivedAvailability<EngineSceneModel>` (already written) + carried channels | No new type; feed channels from `LoadedModel.debugModes` (A3). |
| `AnimationPlaybackController` | `PreviewScene` clip playback + `PreviewClip` | The A2 protocol; back it with the real player. |
| *(optional)* active scene / variants | `HostSidebarModel.activeSceneIndex`, `materialVariantNames` / reload | Required if A4-4 / A4-6 stay YES — either extend seam protocols or keep small host chrome beside PreviewUI. |

*Verify:* adapter unit tests green; no engine changes needed beyond A3.

### B2. Inject into one real window
- New window root hosts `ShellRootView`'s composition with the **engine adapters** and the **real
  canvas**: the generic `canvas: () -> Canvas` closure returns the real `PreviewView`
  (`HostPreviewContainer`/`PreviewHostingView`) instead of `CanvasPlaceholder`. The UI views are
  untouched. **Preserve** `DocumentGroup` / open-URL / drop-open (`GLBDocumentOpening`) / Welcome
  / Sparkle `CommandGroup(after: .appInfo)` — B2 is chrome injection, not a new app lifecycle.
- Wire selection↔`HostSidebarModel` (reuse the existing `PreviewOverlay`/`GLTFNodeLookup` bridge),
  pills→session, screenshot→`viewport.screenshot()`, playback bar→the controller, and (if A4-4/6)
  scene + material-variant switching without regressing re-convert.
- Rebuild the **View menu** as `CommandGroup(after: .sidebar)` driving the seam controllers via the
  existing `FocusedValues` pattern (do **not** add a `CommandMenu("View")`). This **replaces** the
  current host `CommandGroup` body (floor / auto-rotate / center / ortho / double-sided / skeleton /
  FOV / fit / reset / screenshot / presets / lighting) — do not delete in B4 until B2's menu is
  proven feature-complete per A4-7.
- *Verify (AGENTS.md pitfall gauntlet):* open a real file → exactly one "open start" + one
  "open ready", **zero** "Modifying state during view update"; failed URL shows copy, not a spinner;
  first paint isn't blocked on IBL.

### B3. De-couple `PreviewScene` from the old inlined chrome
`PreviewScene` currently *inlines* `PreviewChromeBar`, `PreviewPlaybackBar`,
`PreviewOrientationGizmo`, `PreviewOverlayFacts` (≈ lines 409–454). The new UI supplies overlays, so
the host path must stop drawing them — **but Quick Look depends on the inlined chrome.** Give
`PreviewScene` a **host-bare mode** (overlays come from PreviewUI) while keeping the in-canvas chrome
available for the QL path (per A4 decision 3). *Verify:* host window has no double gizmos/pills; QL
still shows its tap-to-toggle chrome.

### B4. Delete the old host chrome *(outliner + View menu; not QL-shared files yet)*
Once B2/B3 are verified on real windows:
- **Delete now:** `GLBPreview/HostOutlinerView.swift` (host-only).
- **Replace, don't "delete a throwaway block":** the entire `CommandGroup(after: .sidebar)` in
  `GLBPreviewApp.swift` is the current View menu (P5 lighting is only part of it). After B2's
  seam-driven menu lands, remove the old body; keep Sparkle `CommandGroup(after: .appInfo)`.
  Crib `previewGlassButtonStyle` into `Theme/Glass.swift` first if not already (it is, in the shell).
- **Do not delete yet:** `Shared/PreviewChromeBar.swift` / `Shared/PreviewCycleMenu.swift` — QL still
  needs them until B5 carves its two-button chrome. **Never delete** `Shared/PreviewChrome.swift`
  (`PreviewOverlay` / `PreviewInteraction`).
- **Re-home, don't delete the logic:** `HostSidebarModel` + `PreviewSelectionVisuals` become the
  guts of `EngineSelectionModel` (keep the RealityKit visibility/isolate/AABB behaviour).
  `PreviewSessionBindings`/`PreviewFocus` are superseded by the seam controllers — keep only the
  `FocusedValues` plumbing the menu needs (and any A4-7 bridges you chose to keep).
- *Verify:* host builds without `HostOutlinerView`; no dangling refs to it.

### B5. Extensions *(after host UI; carve QL before deleting shared chrome)*
- **Thumbnail:** unaffected — `ThumbnailExtension` already excludes all UI files and renders via
  `StillRenderer`. No change; just re-run its tests.
- **Quick Look — strip it down to a canvas (A4-3).** QL today shows **full** inlined chrome when
  tapped (not already two buttons). Keep **only**: model interaction (orbit / scroll-dolly /
  shift-pan via `PreviewInteraction`), the **bottom-left info readout** (`PreviewOverlayFacts`),
  and **two small glass buttons**: backdrop cycle + auto-rotate (extract from
  `PreviewChromeBar`/`PreviewCycleMenu` + `previewGlassButtonStyle`). **Remove everything else**
  from QL. Then **delete** the remainder of `PreviewChromeBar.swift` / `PreviewCycleMenu.swift`.
  Note: `PreviewPlaybackBar` lives inside `PreviewChromeBar.swift` — PreviewUI `PlaybackBar` must
  already be engine-backed (A2/B1) before this delete. *Verify:* QL a `.glb` in Finder — model
  orbits, info bottom-left, two buttons work, nothing else, no crash.

### B6. Verify across the fixture matrix on real files
Run the UI-BUILD §2 matrix against **real** assets, not mocks:
`plainMesh` (cube), `riggedAnimated` (BoxAnimated), `withLights`/`withCameras`/`missingChannels`
(Khronos samples), `invalidFile` (`scripts/testdata/invalid`), uncentered (`offcenter`), multiScene.
For each: correct sections appear/disappear, validation badge is honest, real-window log is clean.
UI layout/glass regression is Peekaboo on a live `PreviewUIShell` / host window — not a headless
`--snapshot` harness.

### B7. Final cleanup & docs
- Delete `engine-features` branch + `.worktrees/features`; remove the `ui-rebuild` worktree.
- Keep `PreviewUIShell` (A4-5). Update `README.md` (new app UI) and `AGENTS.md` (verification
  ladder uses Peekaboo; no `--snapshot` harness; adjust file-layout notes).
- Squash-merge the cutover branch to `main`.

---

## The linear path
```
A0 finish merge main → ui-rebuild  →  A1 doc fix
   →  A2 seam holes (playback + screenshot + scene/variants)  ∥  A3 engine gaps  ∥  A3b settings + A3c
   →  A4 decisions (incl. variants / session extras)
   →  B0 land PreviewUI  →  B1 adapters  →  B2 inject one window  →  B3 decouple PreviewScene
   →  B4 delete host outliner + old View menu  →  B5 strip QL then delete shared chrome files
   →  B6 matrix  →  B7 cleanup
```
Highest-leverage checkpoint: **B2** (sign off one real window before deleting anything). A0 commit
is done; **merge `main` into `ui-rebuild` before B0**.

## Risk register
| Risk | Mitigation |
|---|---|
| UI work on stale base (behind Track B) | Finish A0 merge/rebase onto current `main`; both schemes build. |
| Quick Look breaks when chrome is deleted | B3 host-bare mode + B5 keep QL chrome; verify in Finder. QL today is **full** inlined chrome — B5 is a real shrink. |
| `PreviewScene` overlays double up | B3 gates inlined chrome to the QL path only. |
| "Modifying state during view update" regressions | B2 real-window log check; adapters do sync in `.onAppear`/`Task { @MainActor }`, never in `init`. |
| Async validation vs sync snapshot | B1 re-snapshot on resolve; `.failed`/`.skipped` surface as copy. |
| Inspector shows wrong material | A3 mesh→material binding before cutover. |
| Silent loss of multi-scene / P40 variants | A4-4/6 + A2 seam (or explicit drop); B2 fixture check. |
| Silent loss of double-sided / skeleton / FOV | A4-7 before B2 View menu rewrite. |
| Delete `PreviewChrome.swift` by name confusion | Ledger: delete `PreviewChromeBar` only; keep `PreviewChrome`. |
| `PreviewPlaybackBar` deleted with chrome file | A2/B1 engine playback before B5 deletes `PreviewChromeBar.swift`. |
| P34 "live defaults" broken | A3c + stop host ContentView seed-once together. |

## What gets deleted (cleanup ledger)
**Delete:** `HostOutlinerView.swift`, old `CommandGroup(after: .sidebar)` body (after B2 replacement),
`engine-features` branch, `.worktrees/features`, `.worktrees/ui` (post-merge), stray `window-*.png`.
**Delete *after* carving what QL keeps:** `PreviewChromeBar.swift`, `PreviewCycleMenu.swift` — first
extract the backdrop-cycle + auto-rotate buttons and `previewGlassButtonStyle` into the trimmed QL
chrome (B5); then delete the rest. **Keep** `PreviewChrome.swift`.
**Re-home (logic kept):** `HostSidebarModel`, `PreviewSelectionVisuals`, `PreviewSessionBindings`/
`PreviewFocus` → engine adapters + FocusedValues plumbing.
**Re-home into the new Settings (do NOT lose — A3b):** `AppLook`/`AppLookStore`/`KhronosEnvironments`
+ custom HDR import, `SettingsAppearance` + appearance, set-as-default-app, show-toolbar/pills,
`AboutSettingsPane` + `GLBUpdateConfig` (Sparkle). Ported into the 3-tab `SettingsRootView`, driven
by the seam store.
**Keep untouched (engine/canvas):** `PreviewView`, `PreviewScene` (core), `PreviewChrome`,
`PreviewCamera`, `PreviewOrientationGizmo`, `PreviewOverlayFacts` (QL's bottom-left readout),
`PreviewSkeletonOverlay`, `PreviewMorph`, `StillRenderer`, `SelectionDetail`, `GLTFSessionDocument`,
`GLTFValidator`, `EntityLoader`, `Shared/Convert/*`, `ThumbnailExtension` engine path, `PreviewUIShell`.

---

## Plan validation (review)

**Verdict: ready with edits** — strategy (seam adapters, host-bare `PreviewScene`, Settings port,
lazy P34 overlay) is sound; several factual assumptions about branch state and engine gaps were
wrong or incomplete and are corrected above.

### Findings by theme

**Reuse**
- Good: adapters over existing `GLTFSessionDocument` / `HostSidebarModel` / `PreviewOverlay` /
  `FocusedValues` / `ShellRootView` canvas injection.
- Overbuilt: A3 “persist debug channels on the document” — `LoadedModel.debugModes` already exists;
  prefer adapter input from the load result.
- Missed reuse: host multi-scene + P40 material variants already ship; cutover must wire or
  explicitly drop them.

**Simplicity**
- A3c lazy overlay is the right simplification of P34 (matches `sessionValue(for:)`).
- Dropping persisted center/projection from Settings (A3b) is simpler than inventing keys DESIGN
  does not want.
- `autoPlay` was incorrectly listed as a Settings port — it is greenfield; keep optional.

**Dependencies**
- A0 merge of `main` → `ui-rebuild` must finish before A3 work that assumes Track B types.
- A2 playback protocol before B4/B5 delete `PreviewChromeBar.swift` (contains `PreviewPlaybackBar`).
- B4 must not delete shared chrome files before B5 carves QL (ordering fixed).
- A4-4/6/7 gate B2 View-menu / outliner scope.

**Verification**
- Real-window log gauntlet + Peekaboo remain correct for this macOS app (not Chrome DevTools).
- Add explicit B2 checks for multi-scene, variants, double-sided/skeleton/FOV (per A4), and
  screenshot save-panel path.
- B5 must verify QL shrink from *full* chrome, not assume two buttons already exist.

**Assumptions / risks**
- §0 “UI untracked / `main == engine-features`” was stale — UI committed; `main` ahead of
  `engine-features`.
- Lighting: `usesStudioEnvironment` ≠ host dim-studio; `AppLook.useEnvironmentMap` can disable IBL.
- Screenshot: `screenshotCurrentCameraPose` is private on `ContentView`, not a Scene/Still API.
- Name trap: `PreviewChrome` (keep) vs `PreviewChromeBar` (delete after B5).
- App lifecycle (DocumentGroup, Sparkle, open/drop) must survive B2 — called out now.

### Edits applied to this doc
1. Rewrote §0 / A0 for current git reality (`ui-rebuild` `ab16854`, `main` `1c3018a`).
2. Thinned A3 debug-channel work to `LoadedModel.debugModes`.
3. Corrected multi-scene, lighting, autoPlay, screenshot, View-menu, and B4/B5 delete ordering.
4. Added A4 decisions for variants + session extras; expanded risk register / cleanup ledger.

### Execution checklist (next)
1. Merge/rebase `main` into `ui-rebuild`; both schemes build + tests.
2. A1 doc fix on reconciled `ENGINE-FEATURE-PACKS.md`.
3. Confirm A4-4/6/7 (scene / variants / double-sided·skeleton·FOV).
4. A2 seam holes (playback, screenshot wire, scene/variants if YES).
5. A3 honesty gaps (bound material; optional material non-optionals) ∥ A3b/A3c settings.
6. B0→B2 one real window; only then B3–B7.
