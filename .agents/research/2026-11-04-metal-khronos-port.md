# Research: porting the Khronos glTF Sample Renderer to native Metal

Date 2026-11-04. Serves [`../plans/2026-11-04-native-metal-khronos-renderer.md`](../plans/2026-11-04-native-metal-khronos-renderer.md).
The question: what already exists (code, tools, evidence) that makes a faithful *and* fast Metal
port succeed, and what traps have others, or this repo, already hit.

## Answer

1. **No open-source project is a faithful Metal port of the Khronos renderer that we can lift.**
   The closest is `khiner/MeshEditor` (GPL-3.0): useful to read for its architecture, but its code
   cannot be copied into an MIT app. Port straight from the pinned Apache-2.0 Khronos GLSL.
2. **Keep the variant count small.** MeshEditor shows that 7 coarse feature function constants
   are enough. Texture presence and UV transforms can be per-material runtime flags: a uniform
   branch gives numerically identical results. So we need no binary archive, and compile cost
   stays flat.
3. **Dependencies are a solved problem in this repo.** GLTFKit2 0.5.15 (MIT, an SPM binary
   xcframework) wraps cgltf, ships a libktx xcframework and meshopt support, and takes a Draco
   plugin. DracoSwift 1.5.7 provides Draco. Both shipped in an extension-safe framework, including
   the thumbnail appex, until `4ab4645`. Restore that wiring instead of choosing between fastgltf
   and cgltf. Only mikktspace needs vendoring.
4. **Pin to `863b981`.** Upstream is 99 commits ahead, with `KHR_materials_scatter`,
   retroreflection, wireframe, a clipping cuboid, and +126 lines in `pbr.frag`. Port the vendored
   commit, because that is what the goldens show. Re-sync later as a diff.
5. **The page's exact texture rules are known:** ASTC 4×4 for KTX2 (if WebKit exposes ASTC), 16×
   anisotropic filtering on trilinear samplers, clamp-to-edge when there are no mips, no Y flip and
   no colour conversion. Each rule is a parity requirement.

## Prior art

| Project | Licence | What it is | Use for us |
| --- | --- | --- | --- |
| [KhronosGroup/glTF-Sample-Renderer](https://github.com/KhronosGroup/glTF-Sample-Renderer) @ `863b981` | Apache-2.0 | The reference: 24 files in `source/Renderer/shaders/` today, 22 in our bundle | **The source of the port.** Keep `NOTICE` and attribution in `RendererMetal/Shaders/UPSTREAM.md` |
| [khiner/MeshEditor](https://github.com/khiner/MeshEditor) (pushed 2026-10-31) | **GPL-3.0** | C++ + Metal editor. `src/shaders/pbr.metal` (523 lines, "Adapted from KhronosGroup/glTF-Sample-Renderer"), `brdf/ibl/tonemapping.metal`, `IblPrefilter.metal`, `TransmissionComposite.metal`, `IridescenceBRDF.metal`. Uses the same three LUT PNGs. Bindless + meshlets | **Read only, never copy.** Confirms the approach (function constants per feature, a transmission prepass flag, prefilter in compute). Its `render/` folder has about 200 per-asset screenshot scripts over glTF-Sample-Assets, used as a smoke corpus. Its pipeline (visibility buffer, meshlets) is far heavier than we need |
| GLTFMetalKit inside [openheart-inc/VRMMetalKit](https://github.com/openheart-inc/VRMMetalKit) (spike: `.claude/worktrees/filament-race/.build/VRMMetalKit`) | Apache-2.0 | Swift + Metal: `GLTFPBRShader.metal` (542 lines), `IBLPrefilter.metal` (330). Core PBR, punctual, unlit, IOR, emissive strength, texture transform only | **The ~120 ms whole-process number** in the baseline. Its BRDF uses UE4 Schlick-GGX (`k = (r+1)²/8`), not Khronos's height-correlated Smith, so it is **not** a parity source. Its compute prefilter and Swift↔Metal plumbing are a readable model |
| [warrenm/GLTFKit2](https://github.com/warrenm/GLTFKit2) 0.5.15 | MIT | ObjC glTF object model over cgltf. `deps/libktx/ktx.xcframework`, `GLTFMeshoptSupport.mm`, a Draco plugin protocol | **The loader.** It was in this repo's `project.yml` until `4ab4645` |
| [warrenm/DracoSwift](https://github.com/warrenm/DracoSwift) 1.5.7 | Apache-2.0 | Draco as an SPM package | Draco decode, via the old `GLBDracoDecompressor.mm` |
| [KhronosGroup/glTF-iOS-Viewer](https://github.com/KhronosGroup/glTF-iOS-Viewer) | Apache-2.0 | Khronos's own iOS app: GLTFKit2 0.5.3 + DracoSwift. Its README lists core + clearcoat, unlit, lights, Draco, meshopt, basisu and texture transform (renderer internals not checked) | Shows that even Khronos ships GLTFKit2 on Apple platforms. Not a fidelity reference |
| [nvpro-samples/vk_gltf_renderer](https://github.com/nvpro-samples/vk_gltf_renderer) | Apache-2.0 | Vulkan + Slang. Every KHR material, plus draft scatter/retroreflection. Its README says the **path tracer** is the reference and the rasterizer is only a preview | Cross-check for material parameter decoding (`shaders/gltf_material_eval.h.slang`). Its maths is stochastic, so it is not a parity source |
| [deeeemiss/Peek3D](https://github.com/deeeemiss/Peek3D) | MIT | A macOS viewer: GLTFKit2 → SceneKit | A competitor, and evidence for GLTFKit2 + DracoSwift + libktx on macOS 13+ |
| [Khronos glTF Render Fidelity](https://github.khronos.org/glTF-Render-Fidelity) | — | Side-by-side renders of sample assets per engine, including `gltf-sample-viewer`, as PNGs at 2048 | An external sanity check per model. Its camera and environment differ from ours, so it cannot replace our goldens |

## Shader translation options

| Option | Verdict |
| --- | --- |
| **Hand port to MSL, file for file** | **Chosen.** Readable, diffable against upstream, and function constants replace `#ifdef`s |
| glslang → SPIR-V → SPIRV-Cross `--msl` | Only as a **checking tool** for one function: its output is flattened per permutation, and specialisation constants do not map from `#ifdef` code |
| [Slang](https://github.com/shader-slang/slang) with GLSL input → Metal | No. GLSL input is "best effort", and the docs warn it is not a drop-in GLSL compiler. It would add a toolchain to the build for code we still have to review line by line |
| Rewrite in Slang once and target Metal | No. It would be a fork of Khronos's maths with no parity benefit |

**Differential function tests (optional, for the tricky ones).** For iridescence (`evalIridescence`),
Charlie sheen, `V_GGX_anisotropic` and volume attenuation, render a 64×64 grid of inputs through the
GLSL function in the WebKit page (a test-only shader writing to an RGBA32F target) and through the
MSL function on Metal, then compare the floats. This finds a porting slip before it gets lost in
a full-frame diff.

## Parity facts read from the pinned bundle

All line numbers are in `git show f1fd1af:Vendor/web-renderer/gltf-viewer.module.js`.

- **Texture upload:** `UNPACK_FLIP_Y_WEBGL false` (10922). Colour space conversion off, premultiply off
  (71413). Colour textures are `SRGB8_ALPHA8`. Mips come from `generateMipmap` when the sampler wants them (10952).
- **Samplers** (`setSampler`, 11080–11125): if there are no mips, wrap becomes `CLAMP_TO_EDGE` and
  min-filter drops to `NEAREST`/`LINEAR`. **16× anisotropic filtering** (`MAX_TEXTURE_MAX_ANISOTROPY`) is applied
  when mag ≠ NEAREST and min is `*_MIPMAP_LINEAR`. Metal: `MTLSamplerDescriptor.maxAnisotropy = 16`
  under the same rule.
- **KTX2 transcode target** (90428–90453): ASTC 4×4 → BC7 → BC1/3 → PVRTC → ETC → RGBA4444, picked
  by which WebGL extensions exist. *Verify in WKWebView which one the page actually gets* (log
  `gl.getSupportedExtensions()` once) and transcode to the same format in Metal. Apple-silicon
  Macs support both ASTC and BC.
- **Main and transmission targets, MSAA, LUTs, IBL parameters:** already in the plan's Context and
  Approach 3.

## Upstream drift (`863b981…main`, checked 2026-11-04)

99 commits. Shader-relevant changes: `pbr.frag` +126/−13, `material_info.glsl` +45, `textures.glsl`
+50/−2, `punctual.glsl` +42/−10, `scatter.frag` +6/−45, a new `wireframe.frag`, `renderer.js` +345/−69.
The newest commits add `KHR_materials_scatter`, which supersedes the volume-scatter path,
`KHR_materials_retroreflection`, a clipping cuboid, and native wireframe. Consequences:

- Port **only** `863b981`. Goldens come from that commit, and the page cannot be re-vendored
  without regenerating them.
- Keep `UPSTREAM.md` with per-function line ranges, so a later re-sync is
  `git diff 863b981..<new> -- source/Renderer/shaders`, replayed onto the MSL.
- Seam 3's volume-scatter work may be replaced upstream soon. Do it last within seam 3.

## Lessons from this repo's earlier renderers

From `git show 687f9b1:.agents/research/2026-10-01-perf-first-pixel.md` and the RealityKit code at `4ab4645^`:

- RealityKit's first frame was slow because texture decode and upload and the clip build were
  **serial on the main actor**, and the float HDR decode was **synchronous on main, redone in every process**.
  The Metal port does the opposite: parallel off-main decode, and an IBL baked at build time.
- WebKit's cost is the page and the process (`pageMs` 200–460 ms process-cold, ~1170 ms
  session-first; first `renderFrame` +140–220 ms for shader link, upload and FBO setup). `loadGltf` itself
  is only 6–32 ms. The parse is not the problem; process start, shader compile and upload are.
- Reusable code at `4ab4645^:RendererRealityKit/`: `Convert/PackedAccessors.swift` (219 lines, accessor
  unpacking), `GLBDracoDecompressor.{h,mm}` (the Draco plugin for GLTFKit2), `GLBTry.{h,mm,swift}`
  (ObjC exception guard), `StillRenderer.swift` (an offscreen `MTLDevice` still in the appex),
  `Convert/TextureTransforms.swift`, `SpecGlossBake.swift` (for reference only: Khronos shades
  spec-gloss natively, so do not bake it).

## Licensing

The app is MIT. Porting Apache-2.0 Khronos code is fine with attribution: keep its `LICENSE.md`
and `THIRD_PARTY_NOTICES` next to the MSL, as `RendererWebKit/web-renderer/` does today.
Do not paste MeshEditor (GPL-3.0) code or close paraphrases of it. GLTFMetalKit (Apache-2.0) may be
adapted with attribution, but its maths differs from Khronos.

## Sources

- [glTF-Sample-Renderer shaders](https://github.com/KhronosGroup/glTF-Sample-Renderer/tree/main/source/Renderer/shaders), GitHub compare API `863b981…main`
- [khiner/MeshEditor](https://github.com/khiner/MeshEditor) (`src/shaders/pbr.metal`, `src/render/PbrFeature.h`, `render/`)
- [openheart-inc/VRMMetalKit](https://github.com/openheart-inc/VRMMetalKit) (`Sources/GLTFMetalKit/Shaders/`)
- [warrenm/GLTFKit2](https://github.com/warrenm/GLTFKit2), [warrenm/DracoSwift](https://github.com/warrenm/DracoSwift)
- [KhronosGroup/glTF-iOS-Viewer](https://github.com/KhronosGroup/glTF-iOS-Viewer) (`Package.resolved`)
- [nvpro-samples/vk_gltf_renderer](https://github.com/nvpro-samples/vk_gltf_renderer)
- [deeeemiss/Peek3D](https://github.com/deeeemiss/Peek3D)
- [Khronos glTF Render Fidelity](https://github.khronos.org/glTF-Render-Fidelity), [about](https://github.khronos.org/glTF-Render-Fidelity/about)
- [Slang Metal target notes](https://shader-slanggithubio-aidanfnv-wip.readthedocs.io/en/latest/_sources/external/slang/docs/user-guide/a2-02-metal-target-specific.md.txt)
- [SPIRV-Cross MSL options (Debian manpage)](https://manpages.debian.org/testing/spirv-cross/spirv-cross.1)
- [Using the Metal 4 compilation API](https://developer.apple.com/documentation/metal/using-the-metal-4-compilation-api.md), [MTL4Archive](https://developer.apple.com/documentation/metal/mtl4archive.md)
