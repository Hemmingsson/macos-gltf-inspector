# glTF Inspector — implementation docs

Pipelines, data flow, and measurements. Product *principles*:
[`DESIGN.md`](../DESIGN.md). Agent/build pitfalls: [`AGENTS.md`](../AGENTS.md).

| Doc | Contents |
| --- | --- |
| [`pipeline-web-renderer.md`](pipeline-web-renderer.md) | WebKit pixels: scheme handler, one `viewer.html`, live vs still |
| [`pipeline-gltf-to-realitykit.md`](pipeline-gltf-to-realitykit.md) | RealityKit convert: GLTFKit2 → Entity (canvas + chrome; no prepare) |
| [`renderer-silos.md`](renderer-silos.md) | Two renderer frameworks; adding / removing a silo |
| [`look-probes.md`](look-probes.md) | Measured RealityKit look constants behind `RealityLook` |
| [`../TestModels/References/README.md`](../TestModels/References/README.md) | Pixel-diff goldens for both renderers |
