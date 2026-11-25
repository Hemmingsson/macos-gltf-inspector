---
name: create-wireframe
description: Create or update glTF Inspector window wireframes and visual documentation for its SwiftUI and Metal UI.
---

# Create a documentation wireframe

Use this skill for the document window, sidebar, canvas controls, inspector, and visible states. For behavior or message order, use [create-diagram](../create-diagram/SKILL.md).

1. Read `DESIGN.md`, `DESIGN.md`, and the relevant SwiftUI/AppKit source under `GLTFInspector/`. Use `assets/docs/window-anatomy.json` and `assets/docs/window-anatomy.mjs` as the existing editable geometry and renderer. Preserve the document-window vocabulary: sidebar, Metal canvas, toolbar clusters, validation, and inspector.
2. Extend or add a JSON spec under `assets/docs/`. Keep dimensions in points, use real labels and controls from the app, and keep geometry in the JSON rather than hard-coding a new export.
3. If the existing `window-anatomy.mjs` can render the change, run it from `assets/docs/`:

   ```sh
   node window-anatomy.mjs window-anatomy.json window-anatomy.svg
   ```

   For a new wireframe renderer, keep it self-contained beside its JSON and write the SVG to `assets/docs/<name>.svg`. Do not rely on hosted wireframe services.
4. Inspect the SVG, including its full bounds, labels, spacing, and light/dark readability. Keep callouts short and show only states that answer the reader's question.
5. Embed the SVG in the relevant documentation with the existing relative `assets/docs/*.svg` pattern. The source JSON and renderer must reproduce the checked-in SVG.

Done means the wireframe matches current app code, its editable source and SVG are both under `assets/docs/`, and the relevant documentation embeds the SVG without duplicate prose.
