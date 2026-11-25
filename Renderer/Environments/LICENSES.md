# Bundled lighting environments

Each `<stem>.metalibl` is the prefiltered image-based lighting (diffuse and specular cube maps,
sheen) produced with the Khronos glTF Sample Renderer filter at commit `863b981`;
`shared.metalibl` holds its BRDF lookup tables. The Field preset was rebaked on 2026-11-25
using that pinned filter; the Studio bakes and shared lookup tables are unchanged.
The Metal renderer reads these baked lighting inputs without filtering at runtime.

The Studio source images are the Khronos
[`glTF-Sample-Environments`](https://github.com/KhronosGroup/glTF-Sample-Environments)
`low_resolution_hdrs` HDRs:

| Bake | Image | Title | SPDX |
|---|---|---|---|
| `field.metalibl` | `noon_grass_1k.hdr` | Noon Grass (Field preset) | Greg Zaal / Poly Haven; CC0-1.0 |
| `neutral.metalibl` | `neutral.hdr` | Studio Neutral | SPDX-FileCopyrightText: 2020 Amazon, LLC. Distributed by Khronos Group; SPDX-License-Identifier: CC-BY-4.0 |
| `Colorful_Studio.metalibl` | `Colorful_Studio.hdr` | Colorful Studio | SPDX-FileCopyrightText: 2020 Amazon, LLC. Distributed by Khronos Group; SPDX-License-Identifier: CC-BY-4.0 |

Upstream licence sidecars: `https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Environments/low_resolution_hdrs/<stem>.hdr.license`

The HDR images were modified by prefiltering them into the bundled cube maps. The Field
preset now uses [Noon Grass](https://polyhaven.com/a/noon_grass) by Greg Zaal, from Poly Haven,
under [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/).
[Poly Haven's asset license](https://polyhaven.com/license) permits commercial use and
redistribution. This replaces the former HDRLabs Field image; that image is no longer bundled
in the current app. The Studio bakes remain under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).

See [Field bake provenance and reproduction](tools/README.md) for source checksums, filter
settings and validation. The preset's stored identifier remains `field`.
