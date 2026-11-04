# glTF Inspector — implementation docs

Pipelines and data flow. Product *principles*: [`DESIGN.md`](../DESIGN.md). Agent/build
pitfalls: [`AGENTS.md`](../AGENTS.md).

| Doc | Contents |
| --- | --- |
| [`renderer-backends.md`](renderer-backends.md) | Which renderer draws each surface (native Metal by default), the `GLTF_RENDERER` overrides, packaging into the extensions |
| [`pipeline-web-renderer.md`](pipeline-web-renderer.md) | The WebKit page (override and pixel-diff oracle): scheme handler, one `viewer.html`, bridge, what each control changes, failure |
| [`../TestModels/References/README.md`](../TestModels/References/README.md) | Pixel-diff goldens |
