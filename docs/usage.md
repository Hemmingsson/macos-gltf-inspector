# Using glTF Inspector

[← README](../README.md)

## Look around

Drag to orbit. **Shift-drag** to pan. Scroll to zoom. **Fit** (⌘9) frames the whole model.

Select a sidebar row to see its properties. Hide or solo nodes, or frame the selection —
none of that changes the file on disk.

Canvas controls cover backdrop, floor, view mode, lighting, and camera.
Only options the open file supports are shown.

## Animation and export

Use the timeline to pick a clip, play, pause, scrub, loop, or change speed.

**Export PNG…** saves the current view. **Export Turntable Video…** / **Export Turntable GIF…**
orbit once around the model. MP4 is H.264 at 30 fps; GIF loops at 15 fps.

## Shortcuts

| Action | Shortcut |
| --- | --- |
| Toggle sidebar | ⌘B |
| Fit model | ⌘9 |
| Frame selection | ⌥⌘F |
| Reset view | ⌘0 |
| Auto-rotate | ⌘R |
| Export PNG | ⌘E |

The menu bar has the rest.

## Finder

**Space** opens Quick Look. Finder also shows thumbnails. Open the app once so the
extensions register. For `.gltf`, keep `.bin` and texture files with the model.

Quick Look spins the camera. Finder previews use the rest pose and ignore hide/solo
from the app window.

## Limits

glTF 2.0 with selected extensions. Animation covers node transforms and morph weights;
animation pointers are ignored.

The built-in validator checks the file, not the renderer. It skips sources larger than
48 MiB. Findings show up in the sidebar and inspector.
