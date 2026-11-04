# Khronos Sample Viewer environments

Each `<stem>.metalibl` is the prefiltered image-based lighting (diffuse and specular cube maps,
sheen) the Khronos glTF Sample Renderer computes from one environment image; `shared.metalibl`
holds its BRDF lookup tables. They were exported once from that renderer at commit `863b981`, so
the Metal renderer lights a model exactly as the Sample Viewer does, without filtering at runtime.

The source images are the Khronos
[`glTF-Sample-Environments`](https://github.com/KhronosGroup/glTF-Sample-Environments)
`low_resolution_hdrs` HDRs:

| Bake | Image | Title | SPDX |
|---|---|---|---|
| `field.metalibl` | `field.hdr` | Field | SPDX-FileCopyrightText: 2020 HDRLabs sampled by UX3D GmbH. Distributed by Khronos Group; SPDX-License-Identifier: CC-BY-NC-SA-3.0 |
| `neutral.metalibl` | `neutral.hdr` | Studio Neutral | SPDX-FileCopyrightText: 2020 Amazon, LLC. Distributed by Khronos Group; SPDX-License-Identifier: CC-BY-4.0 |
| `Colorful_Studio.metalibl` | `Colorful_Studio.hdr` | Colorful Studio | SPDX-FileCopyrightText: 2020 Amazon, LLC. Distributed by Khronos Group; SPDX-License-Identifier: CC-BY-4.0 |

Upstream licence sidecars: `https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Environments/low_resolution_hdrs/<stem>.hdr.license`
