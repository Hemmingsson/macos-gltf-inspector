# Khronos shader port

Source: KhronosGroup/glTF-Sample-Renderer, pinned commit `863b981` (the same
revision in `RendererWebKit/web-renderer/VERSION`). Apache-2.0; see LICENSE.md
and THIRD_PARTY_NOTICES.txt. No MeshEditor source is incorporated.

The readable pinned shader strings can be recovered from repository commit
`f1fd1af:Vendor/web-renderer/gltf-viewer.module.js` (variables listed below).
Metal files were translated by hand. The original function names are retained
where the signatures permit it.

| Metal source | Pinned GLSL string | Functions |
| --- | --- | --- |
| brdf.metal | brdfShader | Fresnel, GGX distribution/visibility, Charlie sheen |
| ibl.metal | iblShader | IBL Fresnel compensation, anisotropic bent normal |
| punctual.metal | punctualShader | Light falloff, spot attenuation, volume rays/attenuation |
| iridescence.metal | iridescenceShader | Thin-film Fresnel and spectral sensitivity |
| tonemapping.metal | tonemappingShader | Neutral, ACES, gamma encoding |
| pbr.metal | pbrShader, primitiveShader, materialInfoShader, texturesShader | Geometry, material textures, shading, output flags |
| ibl_filtering.metal | iblFiltering, panorama-to-cubemap shader | Hammersley integration, filter and LUT kernels |

`ShaderTypes.metalh` is the native buffer ABI. `MetalMaterialUniforms.swift`
and `MetalRenderer.swift` mirror it. Geometry uses an 80-byte packed vertex.
Material maps and samplers use an argument buffer; per-map flags and UV
transforms remain uniform branches.

The environment bake uses the page's actual filtered textures as a fidelity
oracle. The Metal compute port is available for differential tests and future
bake tooling. Runtime uses only bundled binary `.metalibl` assets.

The implementation remains under development: strict pixel parity is the
cutover gate. Run `TEST_RUNNER_GLTF_METAL_PARITY=1 ./scripts/dev.sh test
-only-testing:GLTFInspectorTests/PixelDiffMetalTests`. Do not regenerate the
WebKit references to conceal a port difference.
