# Using glTF Inspector

[← README](../README.md)

## Look around

Drag to orbit the model. Hold **Shift** while dragging to pan. Scroll to zoom.
Use **Fit** (⌘9) to bring the whole model back into view.

Select an item in the sidebar to see its properties in the inspector.
You can hide or solo nodes and frame a selection without changing the source file.

The canvas controls change the backdrop, floor, view mode, lighting, and camera.
Only options supported by the open file are shown.

## Animation and export

Choose a clip in the timeline to play, pause, scrub, loop, or change playback speed.

Choose **Export PNG…** for the current view, or **Export Turntable Video…** /
**Export Turntable GIF…** for a complete orbit. MP4 uses H.264 at 30 fps; GIF loops at 15 fps.

## Shortcuts

| Action | Shortcut |
| --- | --- |
| Toggle sidebar | ⌘B |
| Fit model | ⌘9 |
| Frame selection | ⌥⌘F |
| Reset view | ⌘0 |
| Auto-rotate | ⌘R |
| Export PNG | ⌘E |

The menu bar lists the remaining commands and shortcuts.

## Finder

Select a model and press **Space** for Quick Look. Finder also shows model thumbnails.
Open the installed app once to register its extensions. For `.gltf`, keep referenced
`.bin` and texture files with the model.

Quick Look rotates the camera automatically. Both Finder surfaces show the rest pose,
without the app window’s hidden or soloed nodes.

## Limits

The viewer supports glTF 2.0 and selected extensions. Animation supports node transforms
and morph weights; animation pointer targets are ignored.

The built-in validator checks the file, not the viewer’s rendering. It skips source files
larger than 48 MiB. Findings appear in the sidebar and inspector.
