# UI Implementation Plan — the shell, sliced horizontally

Design: [DESIGN.md](DESIGN.md) · Seam & strategy: [UI-BUILD.md](UI-BUILD.md) · Engine work:
[ENGINE-FEATURE-PACKS.md](ENGINE-FEATURE-PACKS.md).

**How this is sliced.** Horizontally: first we get the *frame* dead-on (window chrome, traffic
lights, the three panels, the canvas region) with everything empty but correctly proportioned.
Only then do we fill each region, then wire behaviour, then polish. Every slice **builds, runs,
and is eyeball-validatable on its own** — you should be able to open the shell after each one and
see a real, if partial, app. Slices are linear (each depends on the previous).

**Why a shell app at all.** We perfect the UI against mock data with zero engine risk, then inject
the real engine behind the same protocols (UI-BUILD §0). The UI code never changes at cutover.

---

## Conventions (read once)

- **Two source folders, not an SPM package.** `PreviewUI/` = seam + views, compiled into
  `PreviewUIShell` now and later into `GLBPreview`. **Never import `Shared/`** (no `EntityLoader`,
  `GLTFAsset`, RealityKit loading, or `PreviewChromeBar`). If `PreviewUI` needs an engine type,
  put it behind a seam protocol instead.
- **The canvas is injected, not imported.** `ShellRootView` is generic (`@ViewBuilder var canvas:
  () -> Canvas`) — do **not** type-erase with `AnyView`. The shell passes the gradient placeholder;
  the real app later passes a `RealityView`.
- **Seam shape.** Read models (`SceneModel`, `Availability`) are value types / struct-backed
  protocols. Stateful ones (`SelectionModel`, `ViewportController`, `SettingsStore`) are
  `@MainActor @Observable` class protocols (`AnyObject`). Own them with `@State` on the
  **window root** (`ShellRootView`), not on `App`.
- **Crib, don't import.** Copy the 8-line `previewGlassButtonStyle` from
  `Shared/PreviewChromeBar.swift` into `Theme/Glass.swift`. Reuse the host's command pattern:
  `FocusedValues` + `CommandGroup(after: .sidebar)` (`GLBPreviewApp.swift`) — do **not** add a
  second `CommandMenu("View")` (SwiftUI inserts that *between* View and Window).
- **AGENTS.md pitfalls apply even here.** Never mutate `@State`/`@Observable` inside `View.init`
  (only `_State(initialValue:)` assignments); do side-effecting sync in `.onAppear`/`.task`.
- **macOS APIs (macOS 26, already in-repo):** `.windowStyle(.hiddenTitleBar)` +
  `.toolbar(removing: .title)` + `.windowResizability(.contentMinSize)`;
  `glassEffect` / `GlassEffectContainer`; `.buttonStyle(.glass)` / `.glassProminent`;
  `Settings {}`; `.keyboardShortcut(_:modifiers:)`.
- **Icons:** SF Symbols only, monochrome, one low-saturation tint per glTF type (DESIGN.md).
  Auto-rotate = `arrow.trianglehead.counterclockwise.rotate.90` (already used); not `rotate.3d`.
- **Wireframes:** `UI-REBUILD/Main@2x.png` / `Inspect@2x.png` plus the HTML tokens in
  `Main-html/Main.dc.html`. DESIGN.md wins on *which* control lives where; the PNG/HTML win on
  spacing and colour.
- **Validate every slice two ways:** (a) open the shell and eyeball it against the wireframe;
  (b) the agent confirms it builds and the named interaction works. Chrome DevTools do not apply
  (native macOS).
- **Mocks do not wait for the engine track.** UI-BUILD §0's "engine already has a full document"
  copy is stale (`GLTFSessionDocument` is slim on `main`). Shell fixtures invent the data.

### File layout we're building toward
```
PreviewUI/
  Seam/            SceneModel.swift, Availability.swift, ViewportController.swift,
                   SelectionModel.swift, SettingsStore.swift, Models.swift (value types)
  Theme/           Theme.swift (colors/tokens), Glass.swift (pill helpers)
  Frame/           ShellRootView.swift, LeftSidebar.swift, RightInspector.swift, CanvasRegion.swift
  Sidebar/         OutlinerSection.swift, NodeRow.swift, NodeIcon.swift
  Inspector/       NodeHeader.swift, TransformSection.swift, MaterialSection.swift, FileSection.swift,
                   ValidationSection.swift
  Toolbar/         StagePill.swift, LookPill.swift, CameraPill.swift, ViewModeMenu.swift, LightingPopover.swift
  Overlays/        OrientationGizmo.swift, DimensionsReadout.swift, PlaybackBar.swift
PreviewUIShell/
  PreviewUIShellApp.swift, Mocks/ (Mock*.swift + Fixtures.swift)
```

---

## Slice 0 — Scaffolding & the seam · *foundation, no visuals*

**Goal:** a `PreviewUIShell` app target that builds and opens an empty window, plus the seam
protocols and one mock, so every later slice has something to compile against.

**Why first:** locking the seam signatures now is what lets the engine track (ENGINE-FEATURE-PACKS)
and this UI track proceed without touching each other.

**Build:**
1. `project.yml` — add a target + scheme. Project-level `settings.base` already sets
   `SWIFT_OBJC_BRIDGING_HEADER` and deployment `26.0`; override the header. No Sparkle / GLTFKit2
   / Draco / Shared sources. Generate Info.plist (don't add a handwritten one):
   ```yaml
   targets:
     PreviewUIShell:
       type: application
       platform: macOS
       sources: [PreviewUI, PreviewUIShell]
       settings:
         base:
           PRODUCT_BUNDLE_IDENTIFIER: com.laurie.PreviewUIShell
           GENERATE_INFOPLIST_FILE: YES
           SWIFT_OBJC_BRIDGING_HEADER: ""
   schemes:
     PreviewUIShell:
       build: { targets: { PreviewUIShell: all } }
       run:   { config: Debug }
   ```
   Then `xcodegen generate`.
2. `PreviewUI/Seam/` — UI-BUILD §0 protocols + value types (`SceneNode`, `NodeKind`, `LightInfo`,
   `MaterialInfo`, `Stats`, `Dimensions`, `ValidationResult`, `PipelineReport`, `ViewMode`,
   `Projection`, `CameraPreset`, `BackdropStyle`). Read protocols may be struct-backed; stateful
   ones are `@MainActor @Observable` `AnyObject` (see Conventions).
3. `PreviewUIShell/Mocks/MockScene.swift` — `@Observable` flag bag **now** (Slice 6 only adds the
   Debug menu). Empty flags = `plainMesh`.
4. `PreviewUIShell/PreviewUIShellApp.swift`:
   ```swift
   @main struct PreviewUIShellApp: App {
     var body: some Scene {
       WindowGroup { Color.clear }
         .windowStyle(.hiddenTitleBar)
         .windowResizability(.contentMinSize)
         .defaultSize(width: 1280, height: 820)
     }
   }
   ```
   On the window's root view (Slice 1): `.toolbar(removing: .title)` so the title string is gone
   but traffic lights remain.

**Validate:**
- `xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme PreviewUIShell -destination 'platform=macOS' -derivedDataPath /tmp/PreviewUIShell-dd build`
- Running it opens one empty, resizable, **title-less** window (traffic lights top-left over the content).

**Depends:** nothing.

---

## Slice 1 — The frame · *traffic lights + three panels + canvas region*

**Goal:** the exact skeleton of the wireframe — three columns at the right widths and colours, the
canvas gradient in the middle, traffic lights clearing the sidebar content, light **and** dark
correct. **No content inside the panels yet** — just labelled empty regions.

**Why:** this is the load-bearing layout. Getting widths, insets, dividers, and dark-mode tokens
right now means every later slice just drops content into a correct box. This is the slice you
sign off on before anything else.

**Build:**
1. `Theme/Theme.swift` — the palette as one source of truth (mirror the wireframe CSS vars), each
   colour defined for light and dark so the whole app themes from here:
   ```swift
   enum Theme {
     static let chrome   = Color(light: .init(white: 0.957), dark: .init(white: 0.13))
     static let border   = Color(light: .black.opacity(0.10), dark: .white.opacity(0.10))
     static let text     = Color(light: .init(white: 0.114), dark: .init(white: 0.95))
     static let text2    = Color(light: .init(white: 0.53),  dark: .init(white: 0.62))
     static let text3    = Color(light: .init(white: 0.65),  dark: .init(white: 0.55)) // --text3
     static let accent   = Color(nsColor: .controlAccentColor)
     // type tints from Main-html :root — mesh #6e6e73, camera #0a84ff, light #f5a623,
     // material #a06bd6, anim #34c759
   }
   ```
   SwiftUI has **no** `Color(light:dark:)`. Add a tiny helper via
   `NSColor(name:dynamicProvider:)` (pick `.darkAqua` vs aqua). Tokens from
   `Main-html/Main.dc.html` `:root`.
2. `Frame/ShellRootView.swift` — the three-column HStack:
   ```swift
   struct ShellRootView: View {
     var body: some View {
       HStack(spacing: 0) {
         LeftSidebar().frame(width: 248)
         Theme.border.frame(width: 1)          // hairline; not Divider() (too thick on macOS)
         CanvasRegion().frame(maxWidth: .infinity)
         Theme.border.frame(width: 1)
         RightInspector().frame(width: 288)
       }
       .frame(minWidth: 900, minHeight: 600)
       .background(Theme.chrome)
       .toolbar(removing: .title)
     }
   }
   ```
   *Why a custom HStack, not `NavigationSplitView`:* the wireframe has fixed-width panels, a custom
   inspector, and a toolbar that floats over the canvas — `NavigationSplitView` fights all three and
   adds its own titlebar behaviour. We get panel collapse later with a simple state toggle (the
   inspector button in the header), which is all a viewer needs.
3. **Traffic-light inset:** wireframe title-row is **44 pt** (`Main-html` traffic-light row). Pad
   the sidebar's first content with `.padding(.top, 44)`. Canvas and inspector go to the top.
4. `LeftSidebar` / `RightInspector` = `Theme.chrome` fills with a temporary `Text("Outliner")` /
   `Text("Inspector")`. `CanvasRegion` = the radial gradient (`RadialGradient` matching the
   wireframe) with a centred SF-Symbol cube placeholder.

**Validate:**
- Open the shell: it reads as the wireframe frame — graphite sidebars, soft gradient canvas,
  hairline dividers, traffic lights not overlapping any text.
- Drag-resize: sidebars hold 248/288, the canvas flexes, nothing clips; `minWidth/minHeight` stop it
  collapsing.
- Toggle System Appearance light↔dark: both look right (no hard-coded whites showing through).

**Depends:** Slice 0.

---

## Slice 2 — Left sidebar (outliner) · *fill the left panel*

**Goal:** the sectioned outliner from a mock `SceneModel`: document header, quiet uppercase section
headers, typed tinted icons, selectable rows with the accent highlight, a hover eye. Sections that
have no members **don't render**.

**Why:** proves the "show only what the model has" rule (DESIGN.md) at the structure level, and
gives us the first real data-driven region. Selection state here feeds the inspector next.

**Build:**
- `Sidebar/NodeIcon.swift` — `NodeKind → (symbol, tint)` map (mesh `cube`/graphite, camera
  `video`/blue, light `sun.max`/amber, material `circle.lefthalf.filled`/purple, animation
  `waveform.path`/green).
- `Sidebar/OutlinerSection.swift` — header + rows, rendered only when non-empty:
  ```swift
  if !section.items.isEmpty {
    Text(section.title).font(.system(size: 11, weight: .semibold))
      .textCase(.uppercase).kerning(0.5).foregroundStyle(Theme.text3)
    ForEach(section.items) { NodeRow(node: $0, selected: sel == $0.id) { select($0.id) } }
  }
  ```
- Drive it from `MockScene` (Slice 0) with the `riggedAnimated` flag set so every section has
  members. Selection is the shell's `@Observable SelectionModel` mock, owned on `ShellRootView`.

**Validate:**
- All populated sections show with correct icons/tints; an empty section (e.g. no Cameras) is
  absent, not blank.
- Click a row → it highlights (accent bg); clicking again deselects.
- Hover a row → the eye appears.

**Depends:** Slice 1. Selection model stub (shared with Slice 3).

---

## Slice 3 — Right inspector · *fill the right panel*

**Goal:** the inspector from the mock: the node header row **with the app actions on it**
(screenshot · open-in · divider · inspector-toggle), then Transform / Geometry / Material (map
chips) / File-stats / Validation sections. Reflects the current selection from Slice 2.

**Why:** completes the static reading of the model and locks the header-row pattern (actions live
here, per your Sketch correction — not in a titlebar).

**Build:**
- `Inspector/NodeHeader.swift` — `HStack { icon; name/kind; Spacer(); actions }`. Icon buttons use
  `Theme/Glass.swift` (`.glass` / `.glassProminent`). `tbtn` is HTML-only.
- Sections as small views bound to `selection.detail` (Transform grid, geometry chips, material map
  chips omitting absent maps, File stat rows, a Validation badge that expands). Use mock data.
- When nothing is selected, show the file-level summary (stats + validation) — the inspector is
  never empty for a loaded model.

**Validate:**
- Select "Body" in the outliner → inspector shows its transform/geometry/material.
- Material chips show only present maps (the mock omits, say, Emissive → no Emissive chip).
- Validation badge renders (green "Valid" for a clean fixture; expands to warnings for the invalid
  fixture in Slice 6).

**Depends:** Slice 2 (selection).

---

## Slice 4 — The three toolbar pills · *fill the canvas top*

**Goal:** Stage / Look / Camera glass pills, positioned leading / center / trailing over the canvas,
with every control from DESIGN.md, wired to a mock `ViewportController` so toggles flip and show
active state. View-mode dropdown (full names) and lighting popover open.

**Why:** this is the heart of "the user controls how it's displayed." Getting the three-cluster
split and the glass right is the biggest visible-polish payoff.

**Build:**
- `Toolbar/*Pill.swift` — three `GlassEffectContainer` pills, absolutely positioned in an overlay on
  `CanvasRegion`:
  ```swift
  CanvasRegion()
    .overlay(alignment: .topLeading)     { StagePill().padding(14) }
    .overlay(alignment: .top)            { LookPill().padding(.top, 14) }
    .overlay(alignment: .topTrailing)    { CameraPill().padding(14) }
  ```
  *Why overlays, not a toolbar:* the wireframe floats them over the 3D content; overlays keep them
  independent of window chrome and let each cluster sit at leading/center/trailing.
- Controls: backdrop swatches, floor, auto-rotate
  (`arrow.trianglehead.counterclockwise.rotate.90`), center, view-mode menu, lighting,
  perspective↔ortho, Fit, camera presets — each calling a `ViewportController` method. Active state =
  `.glassProminent` via `Theme/Glass.swift`.
- `ViewModeMenu` lists full names from `availability.availableDebugChannels` (mock returns the set);
  `LightingPopover` has exposure + env-rotation sliders + a file-vs-studio toggle.

**Validate:**
- Three pills sit leading/center/trailing; glass reads correctly on light and dark backdrops.
- Every toggle flips its active look; the view-mode menu shows full names; the lighting popover opens.
- Mock `ViewportController` receives the calls (print or a debug label) — proves the wiring.

**Depends:** Slice 1 (canvas region). Uses the `ViewportController` mock.

---

## Slice 5 — Canvas overlays · *finish the canvas layer*

**Goal:** orientation gizmo (corner axes), dimensions readout, origin gizmo (shown when Center is
off), and the animation playback bar (shown only when `hasAnimations`).

**Why:** these are the inspector-grade cues that make it feel like a tool, and they exercise the
`Availability`-driven show/hide one more time (playback bar).

**Build:** small overlay views (`OrientationGizmo`, `DimensionsReadout`, `PlaybackBar`) positioned
bottom-leading / bottom-trailing / bottom-center. Playback bar gated on `availability.hasAnimations`.
Origin gizmo gated on the mock viewport's `center == false`.

**Validate:** overlays sit correctly; flip the mock `hasAnimations` → playback bar appears/disappears;
flip Center off → origin gizmo appears.

**Depends:** Slice 4.

---

## Slice 6 — Adaptive UI + the Debug menu · *prove it across models, with no file*

**Goal:** a shell-only **Debug menu** in the macOS menu bar that toggles each capability of the mock
model **live** — validation warnings, multiple scenes, animations, lights, cameras, skin/morphs,
missing material channels, uncentered origin — plus one-click **preset** quick-sets for the UI-BUILD
§2 matrix. Flip any toggle and watch the whole UI add/remove that section or control instantly,
**without loading a single file.**

**Why:** this is the acceptance harness for DESIGN.md's core promise — complexity scales with the
asset. Individual toggles (not just preset fixtures) let you isolate one behaviour at a time and see
exactly what appears/disappears, which is the fastest possible way to validate the adaptive UI and to
reproduce a specific state on demand. It lives only in the shell target, so it can never ship in the
real app.

**Build:**
1. `MockScene` already exists (Slice 0). Finish `apply(_:)` for the UI-BUILD §2 presets
   (`plainMesh`, `riggedAnimated`, `multiScene`, `withLights`, `withCameras`, `missingChannels`,
   `invalidFile`).
2. Debug menu is **shell-only**. Bind it to the **key window** via `FocusedValues` (same `@Entry`
   pattern as `GLBPreviewApp.previewCommands`) — do not put `@State mock` on `App` or every window
   shares one fixture.
   ```swift
   .commands {
     CommandMenu("Debug") {
       Toggle("Validation warnings",        isOn: $mock.hasValidationWarnings)
       // …remaining flags…
       Divider()
       Button("Preset: Plain mesh")        { mock.apply(.plainMesh) }
       Button("Preset: Rigged + animated") { mock.apply(.riggedAnimated) }
       Button("Preset: Invalid file")      { mock.apply(.invalidFile) }
     }
   }
   ```
   `CommandMenu("Debug")` is fine (custom name). `Toggle` needs `@Bindable` on the focused mock.
3. Every section/control reads visibility from `Availability` (no hard-coded `if`).

**Validate (the money shot):**
- With nothing loaded, turn **Validation warnings** on → the inspector badge flips to warnings and
  expands; off → back to green "Valid". Same one-toggle-one-effect for every item.
- **Animations** off → playback bar + Animations section vanish. **Lights** off → Lights section
  gone. **Multiple scenes** off → no Scene switcher. **Missing channels** on → the view-mode menu
  shortens and the absent material chips drop. **Uncentered** on → origin gizmo appears.
- The three presets set several toggles at once and match their UI-BUILD §2 rows.

**Depends:** Slices 2–5.

---

## Slice 7 — Interactions & session state · *make it behave like the app*

**Goal:** real per-window session state (defaults vs session, DESIGN.md three-job rule), live
toggles, selection detail binding, and the macOS **View menu** mirroring the toolbar with shortcuts.

**Why:** this is where the settings model becomes real in the UI, and where AGENTS.md pitfalls bite —
so we do it deliberately, after the layout is stable.

**Build:**
- Mock `SettingsStore` owned on `ShellRootView`: seed from defaults at open, session values stay
  per-window, render reads the effective value. **Never mutate in `init`** — `_State(initialValue:)`,
  sync in `.onAppear` (same shape as `PreviewScene` on `main`).
- View-menu items go in `CommandGroup(after: .sidebar)` with
  `.keyboardShortcut(_:modifiers:)` — not `CommandMenu("View")`. Drive them through
  `FocusedValues` so File → New Window gets an independent session.
- A tiny `Settings {}` scene may hold **defaults only** (DESIGN.md App-default job). Canvas pills
  never write defaults.
- Selection detail flows from `SelectionModel`; popovers/menus become stateful.

**Validate:**
- Toggle floor/auto-rotate from the pill *and* the View menu → both stay in sync, effect is live.
- Open two shell windows → toggling in one does **not** change the other (per-window state).
- No "Modifying state during view update" in the console (AGENTS.md pitfall check).

**Depends:** Slice 6.

---

## Slice 8 — Polish · *ship-quality*

**Goal:** the difference between "looks like the wireframe" and "feels native."

**Build/validate checklist:**
- Dark-mode audit against `Inspect@2x.png` / `Main@2x.png`; fix any borrowed system colours.
- Reduced Motion: auto-rotate and transitions respect it.
- Keyboard: full focus ring path; every actionable control reachable.
- Spacing/typography final pass against the tokens; glass blur/opacity tuning on both themes.
- Empty / loading / failed states for the canvas and panels.
- Accessibility labels on icon-only buttons.

**Validate:** side-by-side with the wireframes in both themes; VoiceOver reads the controls;
Accessibility Inspector is clean.

**Depends:** Slice 7.

---

## The linear path
`0 scaffold → 1 frame → (2 left ∥ 4 toolbar) → 3 right / 5 overlays → 6 adaptive → 7 behaviour → 8 polish`

Slice 2 and 4 both depend only on the frame (different folders). 3 waits on 2 (selection); 5 waits
on 4. Stop after Slice 1 and confirm the frame before filling — highest-leverage checkpoint.

Cutover (UI-BUILD §3) is **out of scope** here.

---

## Plan validation (review)

**Verdict:** ready with edits.

**Reuse.** Folders in `project.yml`, not SPM. Crib glass + `FocusedValues`/`CommandGroup(after:
.sidebar)` from the host. Do not import `Shared/`.

**Syntax / APIs checked (Context7 + in-repo, macOS 26).** `.hiddenTitleBar`,
`.toolbar(removing: .title)`, `.windowResizability(.contentMinSize)`, `GlassEffectContainer`,
`.glass` / `.glassProminent`, `CommandMenu` (custom names only), `@Observable` + `@Bindable` +
`@Entry` FocusedValues. No SwiftUI `Color(light:dark:)` — add `NSColor` dynamic helper. No
`cameraPosition(yaw:)` / `tbtn` / `rotate.3d` / `PreviewDebugMode.Channels`.

**Simplicity.** `MockScene` starts in Slice 0 so Slice 6 is only the menu. Generic canvas, not
`AnyView`. Hairline `Theme.border` instead of `Divider()`.

**Dependencies.** Frame sign-off after 1; then 2 ∥ 4. Mocks do not wait on engine packs. Shell
session is per-window (lives on the window root).

**Verification.** Build with `DEVELOPER_DIR` + `xcodebuild -scheme PreviewUIShell`. Eyeball against
PNGs. Two-window test in Slice 7. No browser.

**Edits applied.** Conventions, Slice 0 target settings, window chrome, 44 pt inset, Theme.text3,
Color helper, MockScene timing, glass/`tbtn`/symbol names, Debug/View menu wiring, short
parallel note. Body otherwise unchanged.
