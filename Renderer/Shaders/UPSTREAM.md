# Khronos shader port

Source: KhronosGroup/glTF-Sample-Renderer, pinned commit `863b981`. Apache-2.0;
see LICENSE.md and THIRD_PARTY_NOTICES.txt. No MeshEditor source is incorporated.

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

`ShaderTypes.metalh` is the native buffer ABI. `MetalMaterialUniforms.swift`
and `MetalRenderer.swift` mirror it. Geometry uses an 80-byte packed vertex.
Material maps and samplers use an argument buffer; per-map flags and UV
transforms remain uniform branches.

Lighting comes from the bundled `../Environments/*.metalibl` bakes: the Khronos
renderer's own filtered cube maps and LUTs, exported once. Nothing is filtered at
runtime.

Accuracy is held by the reference images in `TestModels/References/` (rendered by
the Khronos renderer): `./scripts/dev.sh test` compares every pinned sample and
every feature case. Do not regenerate the references to hide a port difference.
