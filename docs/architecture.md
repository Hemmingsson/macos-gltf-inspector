# Architecture

One Metal renderer draws the app, Quick Look, and Finder thumbnails. GLTFKit2 loads scenes.
Shading, cameras, and draw order are ported from Khronos commit `863b981`. Lighting uses
exported bakes. See [upstream details](../Renderer/Shaders/UPSTREAM.md).

## Modules

![One renderer serves three surfaces](../assets/docs/architecture.svg)

| Target | Owns |
| --- | --- |
| `GLTFCore` | File JSON (`GLTFDocument`, `GLTFDocumentJSON`); Khronos validation in `JSContext` (`GLTFValidator`); look types (`RenderLook`, `RenderViewMode`, `LightingEnvironment`); App Group settings. All targets link it. |
| `Renderer` | `MetalRenderer`, shaders and lighting bakes; `ModelView` and its orbit camera; `ModelCanvas` and `ModelCanvasController`; `ThumbnailRenderer`. The app and both extensions link it. |
| `GLTFInspector` | `DocumentWindowModel` owns the file summary and validation. `ViewState` owns window controls. Features live in Sidebar, Inspector, Toolbar, Settings, and DesignSystem. Shortcuts live in `App/Shortcuts.swift`; menu-only actions such as PNG export live in `App/MenuCommands.swift`. |
| `PreviewExtension` | One `ModelCanvas` with the stored look. |
| `ThumbnailExtension` | `ThumbnailRenderer` writes a PNG for `QLThumbnailReply`. |

Both frameworks are extension-safe. The app embeds them and GLTFKit2 once in
`Contents/Frameworks`. Extensions use `@executable_path/../../../../Frameworks`.

## File loading and view state

![Panels and canvas load in parallel](../assets/docs/open-file.svg)

1. `DocumentWindow` calls `DocumentWindowModel.beginOpen` and logs `open start`.
   `openSummary` parses JSON off the main thread. Panels follow the model's phase.
2. The canvas loads through `ModelCanvasController` and `ModelView` at the same time.
   It applies `ViewState.options`. A panel failure does not hide a rendered model.
3. A ready canvas starts validation once. `ValidationResult` maps findings to outliner rows.

Each open logs `open ready` or `open failed`. The canvas logs `canvas ready` or `canvas failed`.
These outcomes can arrive in either order. Failure ends in `.failed(message)`, not a spinner.
Toolbar, menu, and sidebar controls edit `ViewState`. SwiftUI sends `ViewOptions` through
`ModelCanvas` to the controller. It applies options one call at a time; the latest options win.
Hide/solo, selection, and overlays use this path. Fit, presets, zoom, and PNG export call the controller directly.

![Load states](../assets/docs/load-states.svg)

`DocumentState` has empty, loading, ready, and failed states. A new file cancels validation
and invalidates stale generations. There is no cancelled state. Closing discards the model.
The diagrams show control flow, not frame timing.

## Quick Look and thumbnails

![Hosts, interaction, and output](../assets/docs/surfaces.svg)

Quick Look uses the stored look, floor, rest pose, and automatic camera rotation.
It keeps authored placement unless the model is far from the origin
(`isCentered: false`, `centerWhenFarFromOrigin: true`). Thumbnails use one renderer per process.
Requests run in sequence. Each writes a temporary PNG for `QLThumbnailReply(imageFileURL:)`.
Only the app writes `AppGroupSettings.defaults`. The sandboxed extensions read it.

## Frame passes and accuracy

![Environment, scene passes, tone mapping, then overlays](../assets/docs/frame-passes.svg)

Bind the environment, draw scene passes, then tone map. Draw the floor, grid, selection
outline, and gizmos after tone mapping.

![Reference-image comparisons](../assets/docs/reference-tests.svg)

`TestModels/References/` holds Khronos-style stills: pinned samples in `manifest.json`,
fixed-time poses in `Animated/`, and app features in `Features/`.
`PixelDiffMetalTests`, `FeatureReferenceTests`, and `AnimatedReferenceTests` enforce the
error budgets. Missing samples fail. See [provenance](../TestModels/References/README.md).

## Source map and diagnostics

| Change | Source |
| --- | --- |
| Summary and validation | `GLTFInspector/Window/DocumentWindowModel.swift`, `GLTFCore/GLTFDocument.swift`, `GLTFCore/GLTFValidator.swift` |
| Loading and canvas | `GLTFInspector/Window/DocumentWindow.swift`, `Renderer/ModelCanvas.swift`, `Renderer/ModelView.swift` |
| Passes and overlays | `Renderer/MetalRenderer.swift`, `Renderer/MetalOverlays.swift` |
| Quick Look / thumbnails | `PreviewExtension/PreviewViewController.swift`, `ThumbnailExtension/ThumbnailProvider.swift`, `Renderer/ThumbnailRenderer.swift` |
| Settings and options | `GLTFInspector/App/AppSettings.swift`, `GLTFCore/AppGroupSettings.swift`, `Renderer/ViewOptions.swift` |

`dev.sh run <fixture>` installs in `.build/` and writes `.build/logs/debug.log`; `dev.sh logs` tails it.
Without that file, use `log stream --predicate 'subsystem == "lol.mattias.gltf-inspector"'`.
Categories are `app`, `renderer`, `thumbnail`, and `settings`. Pixel diffs go to
`/tmp/GLTFInspector-pixel-diff/` as `-actual`, `-expected`, and `-diff` PNGs.
`dev.sh bench` reports load, first-still, and GPU times for three samples.
Diagrams use SeeCode specs in `tools/docs/*.json`; generated images live in `assets/docs/`.
To rebuild a diagram, set `SEECODE`, run `node "$SEECODE" render tools/docs/<name>.json`,
then `node "$SEECODE" export tools/docs/<name>.html --formats svg`. Check light and dark
appearance. Use `resvg` for PNG checks. See [development](development.md) for commands.
