# glTF host viewer

The host app is a document viewer with a left outliner. Quick Look and Finder thumbnails stay chrome-less and share the convert + lighting path.

## Surfaces

| Surface | Entry | Render |
|---|---|---|
| Host | `GLBPreviewApp` → `ContentView` | `GLBPreviewView` + `HostSidebarModel` |
| Quick Look | `PreviewViewController` | `GLBPreviewView` (no overlay) |
| Thumbnail | `ThumbnailProvider` | `GLBEntityLoader` + `GLBStillRenderer` |

Load is prepare → GLTFKit2 → `GLBRealityKitConvert` → `Entity` + `GLTFSessionDocument`. Node entities carry `GLTFNodeIDComponent`.

## Default look

`AppLook` (Application Support `look.json`) plus Settings:

1. Convert the default glTF scene.
2. IBL from the selected Khronos HDR (default Studio Neutral) when “Use environment map” is on. `intensityExponent` is 0 with no punctual lights, −2 with lights.
3. File punctual lights stay enabled.
4. Fit camera unless Settings “Default camera” is First file camera.
5. Backdrop is Window / White / Dark — not a skybox. Host uses the Settings background; Quick Look can cycle the same three colors.
6. No custom tone-map post-process.

Changing Environment settings applies on the next open / Quick Look / thumbnail, not to an already-open RealityView.

## Host chrome

Left glass (macOS 26) / material column:

- `GLBPreviewStats` rows
- Scene picker when the file has more than one scene (re-converts that scene)
- Camera picker: Fit + file cameras
- Layer tree: hide and solo (solo hides other **roots** of the active scene)
- Debug: None, Base Color, Roughness, Metalness, Normals, Emission, Wireframe

No right inspector, viewport picking, variant picker, or session-only HDR list.

`HostSidebarModel` (host target) mutates the entity tree via `PreviewOverlay`. Shared preview code does not own hide/solo/debug.

## Settings

Persisted: appearance, quit-on-last-window, auto-rotate, background, play-on-open, Quick Look chrome, default camera, `AppLook`.

Hide/solo/debug/camera/scene are session-only.

## Tests

Proof is `xcodebuild` + `qlmanage` / `--qa-shots`, not a browser.
