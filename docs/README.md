# glTF Inspector — implementation docs

Pipelines, data flow, and decision records for this worktree. Product *principles*:
[`DESIGN.md`](../DESIGN.md). Agent/build pitfalls: [`AGENTS.md`](../AGENTS.md).

| Doc | Contents |
| --- | --- |
| [`decision-web-renderer.md`](decision-web-renderer.md) | Why WebKit + Khronos Sample Renderer; thumbnail entitlement; spike measurements |
| [`pipeline-web-renderer.md`](pipeline-web-renderer.md) | Pixels: scheme handler, one `viewer.html`, live vs still, shared look; measured-and-rejected perf ideas |
| [`pipeline-gltf-to-realitykit.md`](pipeline-gltf-to-realitykit.md) | Host convert: prepare → GLTFKit2 → Entity (inspector / fallback, not the canvas) |
| [`../TestModels/References/README.md`](../TestModels/References/README.md) | Pixel-diff goldens for the JavaScript renderer |
