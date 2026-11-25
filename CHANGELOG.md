# Changelog

## 1.0 — 2026-11-25 (pending release)

First public release candidate: build 4. Requires macOS 26+ on Apple Silicon.

| Type | Changes |
| --- | --- |
| Added | Native glTF 2.0 `.glb` / `.gltf` window, Quick Look, and Finder thumbnails. One Metal renderer serves all three. |
| Added | Inspect scenes, nodes, meshes, materials, cameras, lights, and animation data. Khronos validator findings link to outliner rows. |
| Added | Select, hide, solo, and frame nodes. Change lights, cameras, and view modes. Play and scrub clips. Export PNG, MP4, and GIF. |
| Added | App Group defaults share the stored look with Quick Look and Finder. |
| Fixed | Summary loading keeps custom metadata, unknown extension payloads, and material variant declarations. MP4 export stops if the encoder fails while waiting for a frame. |

Limits: extension support is partial; animation pointer targets are ignored. Validation skips
source files over 48 MiB. Quick Look and thumbnails use the rest pose. Two notarized versions
have not yet passed an end-to-end Sparkle install/relaunch test. Field now uses the CC0 Noon Grass environment; the former restricted Field image is no longer bundled.
