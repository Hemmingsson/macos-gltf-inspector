# Field environment bake

The **Field** preset retains its `field` settings identifier and now uses **Noon Grass**,
a sunny outdoor grass field by Greg Zaal / Poly Haven, licensed CC0-1.0.
This is equivalent outdoor lighting, not a pixel-identical replacement for HDRLabs Field.

- Asset: https://polyhaven.com/a/noon_grass
- License: https://polyhaven.com/license and https://creativecommons.org/publicdomain/zero/1.0/
- Source: https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/1k/noon_grass_1k.hdr
- Source SHA-256: `63413e8b3d8b4c394396d05ab9c7c590a8d70e2cf45187054d198d42f0209939`
- Bake SHA-256: `84bf4ef6eb4626dcc59bce1ca1630b9b6804c41316450366985db4f657ff7ee5`
- Filter: Khronos glTF Sample Renderer `863b981`, recovered unchanged from
  `f1fd1af2bee370818c7e45f638ae6ab8bbfeed04:Vendor/web-renderer/gltf-viewer.module.js`.
  The recovered module SHA-256 is `952702467f109fc7113338167a1f8ede5d9127e6b0e3c3965c5d5f90952963c0`.
- Captured 2026-11-25 using headless Google Chrome with ANGLE Metal, WebGL 2 half-float.
- Upstream defaults: 256px cubes; Lambertian 2048 samples, GGX 1024 samples,
  Charlie sheen 64 samples; LOD bias 0; lowest mip level 4; reported mip count 5.
  Diffuse has six faces at mip 0; specular and sheen have six faces each at mips 0–5.
  Intensity scale is 1. Existing shared BRDF lookup tables are unchanged.

## Reproduce

Use macOS, Swift, Node, Google Chrome at its standard Applications path, and Playwright.
Install Playwright outside the app tree; pass its absolute `index.mjs` path below.
Run from the repository root. The tool reads the pinned filter from the adjacent `upstream/` directory and intercepts
its in-memory browser requests; no web server or remote filter code is used.

```sh
curl -fL https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/1k/noon_grass_1k.hdr -o /tmp/noon_grass_1k.hdr
shasum -a 256 /tmp/noon_grass_1k.hdr
node Renderer/Environments/tools/bake-field.mjs /absolute/path/to/playwright/index.mjs /tmp/noon_grass_1k.hdr /tmp/field.json
swift Renderer/Environments/tools/encode-bake.swift /tmp/field.json /tmp/field.metalibl
shasum -a 256 /tmp/field.metalibl
```

The exporter calls the upstream panorama, Lambertian, GGX and sheen filters without shader
changes, then reads RGBA16F cube faces without rotation or row flips. The Swift step encodes
the existing binary-plist schema and compresses it with LZFSE. Compressed bytes may vary
with platform encoder versions; compare decoded texture bytes when checking reproduction.

## Validation

To validate this recovered export path before replacing the asset, the old source was
recovered from `32cdd5f0^:assets/ibl/khronos/field.hdr` and rebaked. Every half-float component
in all diffuse, specular and sheen faces/mips matched the former `field.metalibl` exactly
(maximum and mean absolute difference both 0). New bake dimensions and counts were checked
by `encode-bake.swift`. All new components are finite and RGB data is nonzero.

The deliberate lighting change affects the `BoomBox-field` image comparison and the Field
lighting documentation image. Existing goldens must be reviewed and replaced using the
independent pinned Khronos renderer with this HDR, not copied from the Metal result.
Unrelated references must stay unchanged.

## Independent Field reference

`render-field-reference.mjs` loads the original pinned Khronos JavaScript renderer, BoomBox,
and the new HDR; it does not invoke the Metal renderer. Run from the repository root:

```sh
node Renderer/Environments/tools/render-field-reference.mjs /absolute/path/to/playwright/index.mjs /tmp/noon_grass_1k.hdr /tmp/BoomBox-field.png
```

Camera: 256², vertical FOV π/4, front-view projected-AABB fit with 1.02 padding,
then azimuth 30° / elevation −20° without re-fitting; target [0,0,0], distance
0.059858935607841245, near 0.000039875311734142786, far 0.3987531173414279.
Look: exposure 0 EV, IBL intensity 1, environment rotation 90°, Khronos PBR Neutral.
Transparent pixels are flattened onto RGB (128,128,128), matching reference conventions.

Before updating the single golden, this harness rendered the original HDR and compared it
against the old golden: mean channel error 0.000931/255 and >16 bad-pixel fraction 0.00003052,
within the existing 1/255 and 0.001 budgets. The new independently rendered Field PNG was
inspected at 256²: model framing is retained, with brighter sky/ground reflections from the
new panorama. No other golden was changed.

The recovered module, supporting files and upstream licenses are retained in `upstream/` so reproduction does not depend on the former private Git history. These are development tools and are not bundled into the app.
