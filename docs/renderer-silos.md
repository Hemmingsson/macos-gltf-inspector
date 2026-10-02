# Renderer silos

Two extension-safe frameworks draw the model. The host and both appexes link both; each
surface picks one at open from `RendererKind` (`Settings ▸ Preview ▸ Renderer`, App Group
suite). Code is the public-API truth — do not keep a second list here.

| Silo | Draws | Convert | Host folder |
| --- | --- | --- | --- |
| `RendererRealityKit/` | `RealityPreviewCanvas` / `StillRenderer` / `RealityThumbnail` | Yes — feeds canvas **and** RealityKit chrome | `GLTFInspector/RealityKit/` |
| `RendererWebKit/` | `WebPreviewCanvas` / `WebRendererHost` (`.live` / `.still`) | **No** — page loads the file; panels from `GLTFDocumentSummary` | `GLTFInspector/WebKit/` |

`GLTFCore/` is shared (JSON document, settings, `RendererKind`, `RenderLook`). `PreviewUI/`
imports neither renderer. `GLTFInspector/` (generic) imports neither renderer.
`GLTFInspector/RendererRouter.swift` is the host's one switch: `#if canImport` mounts
`RealityDocumentWindow` or `WebDocumentWindow`. Quick Look (`PreviewExtension/`) and
thumbnails (`ThumbnailExtension/`) each have a RealityKit file and a WebKit file behind the
same switch.

Each canvas exposes `static let features: Set<RendererFeature>`. Host chrome a renderer
cannot drive is hidden through `RendererAvailability` / `canHideNodes`, not `if renderer ==`.

## Adding renderer-specific code

Only these may `import RendererRealityKit` / `RendererWebKit`:

- `GLTFInspector/RealityKit/` and `GLTFInspector/WebKit/`
- the two router files (`GLTFInspector/RendererRouter.swift`, plus the Quick Look /
  thumbnail routers)
- `GLTFInspectorTests/RealityKit/` and `GLTFInspectorTests/WebKit/`
- a test file gated on both `canImport`s

Root tests import `GLTFCore` / the host / `PreviewUI` — never a renderer.

## Removing a renderer

Delete its framework dir + target in `project.yml` (and its lines in the host / extension /
test `dependencies:`), its adapter files (`GLTFInspector/<Renderer>/`,
`PreviewExtension/QuickLook<Renderer>.swift`,
`ThumbnailExtension/Thumbnail<Renderer>.swift`) and `GLTFInspectorTests/<Renderer>/`.
Nothing else needs an edit: the routers are `#if canImport(Renderer…)`. Optionally drop
`TestModels/References/<renderer>/` and its manifest tolerance. Build clean (a stale
framework module left in DerivedData would keep `canImport` true).
