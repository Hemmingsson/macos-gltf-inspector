# glTF Inspector

macOS 26+ viewer for `.glb` / `.gltf`: a document window, a Quick Look preview and Finder
thumbnails, all drawn by one renderer, the native Metal port of the Khronos glTF Sample Renderer.
The sidebar and inspector show what the file's JSON contains (`GLTFDocument`). How it fits
together: [`docs/architecture.md`](docs/architecture.md).

**New features, UX, or chrome:** [`DESIGN.md`](DESIGN.md) (principles, not layout; code wins).

**Icons:** Prefer a mapped custom glyph when we have one (Blender UI SVGs under
`GLTFInspector/DesignSystem/Icons/BlenderIcons.xcassets` for lights — GPL, see
`BlenderIcons.NOTICE.md`). **SF Symbols are always the fallback** when no catalog image is
mapped (`DSTypeIcon` / `systemImage(for:)`). Do not invent new SF-only mappings that fight a
Blender/Spline reference we already decided to ship as custom art.

## Layout

| Path | Role |
| --- | --- |
| `GLTFCore/` | Framework. What a file contains (`GLTFDocument`, `GLTFDocumentJSON`), the validator, the look vocabulary (`RenderLook`, `RenderViewMode`, `LightingEnvironment`), App Group settings, logging. No AppKit / SwiftUI. |
| `Renderer/` | Framework. `MetalRenderer` (scene loading, shaders, lighting bakes in `Environments/`), `ModelView`, `ModelCanvas` + `ModelCanvasController`, `ThumbnailRenderer`. Extension-safe. |
| `GLTFInspector/` | The app. `App/` (entry, `AppSettings`, menus, `Shortcuts`), `Window/` (`DocumentWindowModel`, `ViewState`, layout), `Canvas/`, `Sidebar/`, `Inspector/`, `Toolbar/`, `Settings/`, `Document/` (display of `GLTFDocument`, `ValidationResult`), `DesignSystem/` (tokens + glass; no Renderer / GLTFCore). |
| `PreviewExtension/` / `ThumbnailExtension/` | Quick Look preview / Finder thumbnail. |
| `GLTFInspectorTests/` | Unit and reference-image tests. References: `TestModels/References/`. |
| `GLTFInspectorUITests/` | Opt-in real-window XCUITest flows. |

## Commands & build

```bash
./scripts/dev.sh install   # build into .build/ (+ /Applications on main); does not open
./scripts/dev.sh test      # branch DerivedData; includes every reference image
./scripts/dev.sh run cube  # install + open a fixture; logs → .build/logs/debug.log
./scripts/dev.sh logs
./scripts/dev.sh uitest    # opt-in; steals focus
./scripts/dev.sh bench     # opt-in load / still / GPU timings
./scripts/build.sh         # install to /Applications + verify (main checkout only)
./scripts/verify.sh
./scripts/release.sh
./scripts/fetch-test-models.sh
./scripts/regenerate-pixel-references.sh
```

**Agents:** `dev.sh install` / `dev.sh test`; never `open` or `build.sh` unless asked to launch.
`dev.sh` DerivedData: `/tmp/GLTFInspector-<branch-slug>-dd` (`scripts/lib/dev-env.sh`). Plain
`xcodebuild` uses Xcode's default DerivedData. `project.yml` (XcodeGen) is the project; the
`.xcodeproj` is generated.

**Renderer regressions:** `TestModels/References/` holds images rendered by the Khronos Sample
Renderer; the Metal renderer must match them. Failures write PNGs to
`/tmp/GLTFInspector-pixel-diff/`. Missing samples **fail**.
[`TestModels/References/README.md`](TestModels/References/README.md).

Signing: `project.yml`. Fixtures: `TestModels/Fixture Models/` via
`GLTFInspectorTests/TestFixtures.swift`. In-memory test GLBs: `GLTFInspectorTests/TestGLBFixtures.swift`.

## Worktrees & what ships

| Source | Treat as |
| --- | --- |
| `main` (merged commits) | Shipped behavior |
| git worktrees (gitignored) | Throwaway until merged |
| `.agents/` plans, handoffs, prompts | Intent only |

Before `git worktree remove`: `git log main..<branch>`. **`DESIGN.md`**: principles only; never
paste shipped layout.

## Pitfalls — do not repeat

**1. SwiftUI state in `init`** — dual spinners, 0 windows, `Modifying state during view update`.
`init` assigns props / `_State(initialValue:)` only; sync in `onAppear` / actions. Under
`@Observable`, a `didSet` that assigns its own property recurses: clamp in a computed setter.

**2. Failed loads** — always `.failed(message)`, never a spinner. The canvas reports
`ModelCanvasController.phase`; a JSON panel failure only fails the panels, never the canvas.

**3. First paint** — the JSON panels and the renderer load in parallel; the canvas region
follows `DocumentWindow.canvasState`. `ModelCanvasController` (owned by `ViewState`) outlives a
remount of the canvas view and keeps its `ModelView`.

**4. Extension sandbox** — settings only via the App Group (`AppGroupSettings`, `AppSettings`).
Never `UserDefaults.standard` for settings; only the app writes the group (`defaults write` hits
another domain). Thumbnails reply with `QLThumbnailReply(imageFileURL:)`.

**5. Reference images** — a missing sample **fails**. Regenerating replaces Khronos's output
with ours: only for a new sample or a deliberate renderer change, after comparing with the
Khronos Sample Viewer. Look at the PNGs.

**6. One renderer.** Window, Quick Look and Finder thumbnail use the same `Renderer` code. Do not
add a renderer setting, a per-surface renderer, or chrome the renderer cannot drive: playback,
morph weights, hide/solo, double-sided, skeleton, a file-light picker, or a custom HDR. The
renderer draws the bind pose; the inspector may still list animations, morphs and skins.

**7. Real-window verify** (unit tests miss **1**): in a worktree `./scripts/dev.sh run <fixture>`
opens the `.build` app; on main `./scripts/build.sh` installs to `/Applications`. Expect one
`open start`, one `open ready` / `open failed`, one `canvas ready` / `canvas failed`, and no
Modifying-state warnings.

**8. UI verification** — skill `macos-app-testing`. Background only: no focus steal, no
`--snapshot`, no leftover Export sheets. Outliner rows select through accessibility
(`AXSelected`) without raising the window.
