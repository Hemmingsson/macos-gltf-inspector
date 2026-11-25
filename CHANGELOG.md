# Changelog

## 1.0 — 2026-11-25

First public release. Build 4. macOS 26+ on Apple Silicon.

### Added

- Native `.glb` / `.gltf` window, Quick Look, and Finder thumbnails — one Metal renderer for all three
- Inspect scenes, nodes, meshes, materials, cameras, lights, and animation
- Khronos validator findings linked to outliner rows
- Select, hide, solo, and frame nodes; lighting, cameras, and view modes; clip playback
- Export PNG, MP4, and GIF
- App Group settings shared with Quick Look and Finder

Limits: partial extension coverage; animation pointers ignored; validation skipped above 48 MiB;
Quick Look and thumbnails use the rest pose.
