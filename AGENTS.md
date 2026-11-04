# glTF Inspector

macOS 26+ viewer for `.glb` / `.gltf`: document window, Quick Look preview and Finder
thumbnail, all drawn by one Metal port of the Khronos glTF Sample Renderer.

- How it fits together: [`docs/architecture.md`](docs/architecture.md)
- Product and UX principles: [`DESIGN.md`](DESIGN.md)

## Layout

| Path | Role |
| --- | --- |
| `GLTFCore/` | What a file contains (`GLTFDocument`), validator, look vocabulary, App Group settings, logging. No UI. |
| `Renderer/` | `MetalRenderer`, `ModelView`, `ModelCanvas` + `ModelCanvasController`, `ThumbnailRenderer`. Extension-safe. |
| `GLTFInspector/` | The app, grouped by feature: `App/`, `Window/`, `Canvas/`, `Sidebar/`, `Inspector/`, `Toolbar/`, `Settings/`, `Document/`, `DesignSystem/`. |
| `PreviewExtension/`, `ThumbnailExtension/` | Quick Look preview, Finder thumbnail. |
| `GLTFInspectorTests/`, `GLTFInspectorUITests/` | Unit + reference-image tests; opt-in XCUITest. |

`project.yml` (XcodeGen) is the project; the `.xcodeproj` is generated.

## Commands

```bash
./scripts/dev.sh install   # build into .build/ (on main also /Applications)
./scripts/dev.sh test      # all tests, including reference images
./scripts/dev.sh run cube  # install + open a fixture; logs in .build/logs/debug.log
./scripts/dev.sh uitest    # XCUITest; steals focus
./scripts/dev.sh bench     # load / first-still / GPU timings
```

## Rules

- **One renderer** for window, Quick Look and thumbnail. No renderer setting, no second renderer.
- **Settings** only through the App Group (`AppGroupSettings`). Only the app writes it.
- **Reference images** in `TestModels/References/` come from the Khronos renderer; ours must
  match. A missing sample fails. Regenerate only for a new sample or a deliberate renderer
  change, and look at the PNGs. Diffs land in `/tmp/GLTFInspector-pixel-diff/`.
- **SwiftUI `init`** only assigns; sync state in `onAppear` or actions. Under `@Observable`, don't
  assign a property in its own `didSet`.
- **Failed loads** end in `.failed(message)`, never a spinner.
- **Icons**: a mapped Blender / Spline glyph first, SF Symbols as fallback (`DSTypeIcon`).
- **Verify UI on screen** with `dev.sh run <fixture>`: one `open start`, `open ready|failed`,
  `canvas ready|failed`, and no "Modifying state during view update" warnings.
- Work on `main`; `.agents/` plans and handoffs are intent, not shipped behavior.
