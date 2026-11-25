---
name: create-diagram
description: Create or update technical diagrams that explain glTF Inspector architecture, loading, rendering, validation, or extension behavior.
---

# Create a documentation diagram

Use this skill for dependencies, data flow, load sequences, state transitions, and other behavior. For visible window layouts, use [create-wireframe](../create-wireframe/SKILL.md).

1. Read the relevant source in `GLTFCore/`, `Renderer/`, `GLTFInspector/`, `PreviewExtension/`, or `ThumbnailExtension/`. Verify every arrow and label against code. Keep the one-renderer relationship intact: `Renderer` feeds the app window, `PreviewExtension`, and `ThumbnailExtension`.
2. Keep the editable source in `assets/docs/<name>.json`. Follow the existing `assets/docs/architecture.json`, `open-file.json`, and `reference-tests.json` shape and concise labels. Use `assets/docs/architecture.svg` as the visual and accessibility reference. Do not create a Mermaid source or a manually positioned one-off SVG.
3. Render the JSON with the repository's `seecode` installation, following the CLI instructions available in that installation. The repository documents that its diagrams are rendered from `assets/docs/*.json`; if `seecode` is unavailable, preserve the JSON and report that SVG rendering could not be verified.
4. Write the rendered SVG beside its JSON as `assets/docs/<name>.svg`. Inspect the SVG bounds, arrow routing, label spacing, and dark/light readability. Do not include a generated page header in the delivered SVG.
5. Embed the SVG in the relevant `README.md`, `ARCHITECTURE.md`, or `DESIGN.md` section using the same relative-image pattern already used in this repository.

Keep the diagram understandable without hover text. Use short node names, meaningful subtitles, and branch labels. A completed diagram has a checked source arrow, a matching SVG under `assets/docs/`, and a documentation embed that renders from the checked-in JSON.
