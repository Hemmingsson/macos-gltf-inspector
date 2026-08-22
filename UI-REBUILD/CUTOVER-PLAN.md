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

## 0. Where we actually are (verified 2026-08-22)

Read this first — three findings reshape the work, and two docs are currently lying.

1. **The entire new UI is uncommitted.** `PreviewUI/` and `PreviewUIShell/` exist **only as
   untracked files in the `.worktrees/ui` working tree** (`git status` → `?? PreviewUI/`,
   `?? PreviewUIShell/`). The `ui-rebuild` branch itself is at `f5229f2` — **one commit *behind*
   `main`** (it predates the engine-features landing) and contains none of the UI code. One
   `git clean`, a worktree prune, or a disk mishap destroys all of it. **This is the single
   biggest risk in the whole effort and A0 fixes it first.**

2. **`engine-features` is already fully merged into `main`.** Both branches point to the same
   commit `a7e9199` ("Land Track B engine feature packs"). Everything the packs doc tags
   "DONE (features)" is literally on `main`, with Swift Testing coverage. The `engine-features`
   branch and `.worktrees/features` are now redundant.

3. **The shell is done and green.** All 8 slices are implemented; `PreviewUIShell` builds
   (`** BUILD SUCCEEDED **`), and carries **no TODO/FIXME/stub/`fatalError`**. UI proof is
   Peekaboo on a live window (no headless `--snapshot` / flatten-glass harness). The seam
   (5 protocols + rich value types) is coherent and fully mock-backed.

**Two stale docs to correct (they will mislead whoever executes this):**
- `ENGINE-FEATURE-PACKS.md` P17 says the glTF validator is *"still absent — cherry-pick from
  engine-features."* **False.** `Shared/GLTFValidator.swift`, `Vendor/gltf-validator/`, the
  invalid fixture, `GLTFValidatorTests`, and host wiring are all on `main`.
- The whole-doc framing *"Status on engine-features"* is obsolete now that `main == engine-features`.

---

# Part A — Fixes & cleanup before the cutover

Goal: eliminate risk, correct the record, close the real seam/engine gaps, and make the product
decisions — so Part B is pure, low-surprise adapter work.

### A0. De-risk: get the UI work into git *(do this before anything else)*

Work in `.worktrees/ui`. The `ui-rebuild` branch is behind `main` and the UI is untracked.

1. **Commit the UI first, exactly as it stands** (so it exists in history before any rebase):
   `git add PreviewUI PreviewUIShell project.yml` and the modified docs, commit on `ui-rebuild`.
2. **Rebase `ui-rebuild` onto `main`** (`a7e9199`) so it becomes *main + UI*. Expect one
   `project.yml` conflict (the shell adds a 4th target + scheme; take both sides). After rebase,
   `PreviewUIShell` must still build.
3. **Reconcile the doc drift.** `main` already has committed `DESIGN.md` / `UI-BUILD.md` /
   `ENGINE-FEATURE-PACKS.md` (from `f5229f2`); the worktree has *modified* copies plus untracked
   `PROMPT-UI.md` and `UI-IMPLEMENTATION-PLAN.md` (the latter two are also untracked in `main`'s
   working tree). Pick the worktree versions as canonical, fold in the A1 corrections, commit once.
4. Push `ui-rebuild` to the remote. **Now the work is safe** and the rest of Part A can proceed on
   that branch.

*Output of A0:* one branch (`ui-rebuild`) = `main` + `PreviewUI` + `PreviewUIShell`, building, pushed.

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
- **Multi-scene switching decision (A4).** The outliner *lists* scenes but nothing sets the active
  scene, and `Availability.isMultiScene/hasCameras/hasSkin/hasMorphs` have no view reader (empty
  sections carry the adaptivity today). If multi-scene switching ships in v1, add
  `setScene(_:)`/`activeSceneID` to the seam now.

### A3. Close the engine gaps on `main` so the adapter stays thin

Each engine pack is real; the gaps below are what the seam asks for that the document/engine does
**not** yet stamp. Order is by "does the inspector actually need it." Land these on `main` (or the
cutover branch) with the existing test fixtures — every one is testable in the current app today.

**Needed for correctness (do before cutover):**
- **`availableDebugChannels` without JSON.** `PreviewDebugMode.available(from: json)` needs the raw
  glTF header, which `GLTFSessionDocument` drops. Compute the channel set at convert time and
  persist it on the document (or a sidecar) so the adapter can serve `Availability` from a snapshot.
- **Persisted `center` + `projection` settings keys.** Today these are session-only `@State`
  (`sessionCenterModel`, `sessionOrthographic`) with **no `UserDefaults` default**. `SettingsStore.
  default(for:)`/`promoteToDefault` need real keys. Add two keys + register defaults
  (mirror `autoRotate`'s registration in `GLBPreviewApp.swift`).
- **Per-node bound material (inspector honesty).** `SelectionDetail`'s materials are the *file-level
  inventory*, not the node's bound material — the code comment admits the mesh→material bind isn't
  on the document. Left as-is, `NodeDetail.material` shows the wrong material, violating DESIGN.md's
  "inspector honesty." **Stamp mesh→material binding** in `RealityKitConvert.makeDocument`.

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
`usesStudioEnvironment` isn't independently toggleable — studio IBL is always on, only dimmed),
selection **toggle-vs-set** (`HostSidebarModel.selectNode`/`isolate` toggle; seam `select(_)`/
`isolate(_)` are set-with-nil-to-clear).

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

Expand the seam's `SettingKey` set (appearance, showPills, useEnvironmentMap, environmentCatalog,
customEnvironmentFile, autoPlay), split by job, and rebuild `SettingsRootView`'s 3-tab `TabView`
(General / Preview / About) hosting the ported panes, driven by the seam store.

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
| 4 | **Multi-scene switching in v1?** | Product call | If yes, A2 adds `setScene` to the seam before cutover; if no, the scene switcher stays a listing only. |
| 5 | **Keep `PreviewUIShell` after cutover?** | **Keep** | Zero-engine-risk design playground + `--proof-outliner`; it never ships. UI regression = Peekaboo on a live window. |

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
| `EngineViewportController: ViewportController` | `PreviewScene` session state + `PreviewCamera` + `FocusedPreviewCommands` + `StillRenderer` | Cleanest — every member has a backer. `screenshot()`→`screenshotCurrentCameraPose`. Map `LightingSettings`. |
| `EngineSelectionModel: SelectionModel` | `HostSidebarModel` + `PreviewSelectionVisuals` + `SelectionDetail` | Reconcile toggle-vs-set; `isVisible` from `hide`+`soloHides`; honest `NodeDetail.material` (A3). |
| `EngineSettingsStore: SettingsStore` | `SettingsKeys` (`@AppStorage`) + per-window session | Resolves P34 (per-window). Type-erased `UserDefaults` bridge for the generic `default(for:)`. |
| `Availability` | `DerivedAvailability<EngineSceneModel>` (already written) + carried channels | No new type; feed it the A3 channel set. |
| `AnimationPlaybackController` | `PreviewScene` clip playback + `PreviewClip` | The A2 protocol; back it with the real player. |

*Verify:* adapter unit tests green; no engine changes needed beyond A3.

### B2. Inject into one real window
- New window root hosts `ShellRootView`'s composition with the **engine adapters** and the **real
  canvas**: the generic `canvas: () -> Canvas` closure returns the real `PreviewView`
  (`HostPreviewContainer`/`PreviewHostingView`) instead of `CanvasPlaceholder`. The UI views are
  untouched.
- Wire selection↔`HostSidebarModel` (reuse the existing `PreviewOverlay`/`GLTFNodeLookup` bridge),
  pills→session, screenshot→`viewport.screenshot()`, playback bar→the controller.
- Rebuild the **View menu** as `CommandGroup(after: .sidebar)` driving the seam controllers via the
  existing `FocusedValues` pattern (do **not** add a `CommandMenu("View")`).
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

### B4. Delete the old chrome
Once B2/B3 are verified on real windows:
- **Delete:** `GLBPreview/HostOutlinerView.swift`, `Shared/PreviewChromeBar.swift`,
  `Shared/PreviewCycleMenu.swift`, and the throwaway `.commands` block in `GLBPreviewApp.swift`
  (the P5 lighting group + preset buttons). Crib `previewGlassButtonStyle` into `Theme/Glass.swift`
  first if not already (it is, in the shell).
- **Re-home, don't delete the logic:** `HostSidebarModel` + `PreviewSelectionVisuals` become the
  guts of `EngineSelectionModel` (keep the RealityKit visibility/isolate/AABB behaviour).
  `PreviewSessionBindings`/`PreviewFocus` are superseded by the seam controllers — keep only the
  `FocusedValues` plumbing the menu needs.
- *Verify:* `xcodebuild -scheme GLBPreview` builds with the files gone; grep confirms no dangling refs.

### B5. Extensions *(do this AFTER the app UI is in — easier once the pieces exist)*
- **Thumbnail:** unaffected — `ThumbnailExtension` already excludes all UI files and renders via
  `StillRenderer`. No change; just re-run its tests.
- **Quick Look — strip it down to a canvas (A4-3).** QL is the lighter, canvas-only preview. Keep
  **only**: model interaction (orbit / scroll-dolly / shift-pan via `PreviewInteraction`), the
  **bottom-left info readout** (`PreviewOverlayFacts` — dimensions/stats), and **two small glass
  buttons reusing main's controls**: backdrop cycle and auto-rotate toggle (carve a trimmed
  chrome from the old `PreviewChromeBar`/`PreviewCycleMenu` bits + `previewGlassButtonStyle` before
  B4 deletes the rest). **Remove everything else** from QL — no pills cluster, no outliner, no
  view-mode/lighting/floor/presets, no menu. This rides on `PreviewScene`'s host-bare core (B3) plus
  the two-button QL chrome. *Verify:* QL a `.glb` in Finder — model orbits, info shows bottom-left,
  the two buttons work, nothing else present, no crash.

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
A0 de-risk (commit ✅ done — still merge main in)  →  A1 doc fix
   →  A2 seam holes  ∥  A3 engine gaps  ∥  A3b settings migration + A3c propagation  →  A4 decisions
   →  B0 land PreviewUI  →  B1 adapters  →  B2 inject one window  →  B3 decouple PreviewScene
   →  B4 delete old chrome  →  B5 strip Quick Look (canvas + info + 2 buttons)  →  B6 matrix  →  B7 cleanup
```
Highest-leverage checkpoint now: **B2** (sign off one real window before deleting anything). A0's
commit is done — the UI work is safe; the branch still needs `main` merged in before hosting B0.

## Risk register
| Risk | Mitigation |
|---|---|
| UI work lost (untracked, on a stale branch) | **A0 first**, commit before rebase, push. |
| Quick Look breaks when chrome is deleted | B3 host-bare mode + B5 keep QL chrome; verify in Finder. |
| `PreviewScene` overlays double up | B3 gates inlined chrome to the QL path only. |
| "Modifying state during view update" regressions | B2 real-window log check; adapters do sync in `.onAppear`/`Task { @MainActor }`, never in `init`. |
| Async validation vs sync snapshot | B1 re-snapshot on resolve; `.failed`/`.skipped` surface as copy. |
| Inspector shows wrong material | A3 mesh→material binding before cutover. |

## What gets deleted (cleanup ledger)
**Delete:** `HostOutlinerView.swift`, the throwaway `.commands` block, `engine-features` branch,
`.worktrees/features`, `.worktrees/ui` (post-merge), stray `window-*.png`.
**Delete *after* carving what QL keeps:** `PreviewChromeBar.swift`, `PreviewCycleMenu.swift` — first
extract the backdrop-cycle + auto-rotate buttons and `previewGlassButtonStyle` into the trimmed QL
chrome (B5); then delete the rest.
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
