# glTF Inspector — implementation docs

Pipelines, data flow, and decision records. Product *principles*:
[`DESIGN.md`](../DESIGN.md). Agent/build pitfalls: [`AGENTS.md`](../AGENTS.md).

| Doc | Contents |
| --- | --- |
| [`decision-web-renderer.md`](decision-web-renderer.md) | Historical WebKit-everywhere decision (superseded by the renderer switch) |
| [`pipeline-web-renderer.md`](pipeline-web-renderer.md) | WebKit pixels: scheme handler, one `viewer.html`, live vs still |
| [`pipeline-gltf-to-realitykit.md`](pipeline-gltf-to-realitykit.md) | RealityKit convert: GLTFKit2 → Entity (canvas + chrome; no prepare) |
| [`renderer-silos.md`](renderer-silos.md) | Two renderer frameworks; adding / removing a silo |
| [`../TestModels/References/README.md`](../TestModels/References/README.md) | Pixel-diff goldens for both renderers |
