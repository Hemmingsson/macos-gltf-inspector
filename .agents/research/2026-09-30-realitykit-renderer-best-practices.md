# RealityKit renderer: simplification and best practices (research)

Date: 2026-09-30 · Repo: `main` @ `a4a4a2f` · Feeds: `.agents/plans/2026-09-30-renderer-separation.md` (seam 5, `RendererRealityKit`)
Scope: research only. No product code changed.

## Answer first

1. **There is still no native glTF path.** `Entity(contentsOf:)` loads only USD and `.reality` files ([docs](https://developer.apple.com/documentation/realitykit/entity/init(contentsof:withname:))).
   I checked this on this machine (macOS 27.0, build 26A428) with a probe program. `Entity(contentsOf: tiny.glb)` throws `importFailureWithURL`, and `MDLAsset.canImportFileExtension("glb"/"gltf")` returns `false`. The WWDC25 `Entity(from: Data)` API supports "same formats" only. So GLTFKit2 plus our own converter remains the only path.
2. **The whole byte-rewrite prepare pass is the main thing to delete.** It parses the GLB, rewrites it, serializes a temp GLB, re-parses it, and can retry on the original.
   GLTFKit2 already handles every input the prepare pass exists for:
   - WebP: `texture.webpSource` is decoded by ImageIO in `newCGImage`.
   - `KHR_mesh_quantization` and integer accessors: `GLTFTransformPackedDataToFloat`.
   - `EXT_mesh_gpu_instancing`: `GLTFNode.meshInstances`.
   - Unnamed joints: we already resolve them at convert with `Skin.resolvedName`.

   Spec-gloss is the only step that truly needs pixel work, and it can run at convert time. EXP-016 did this at −187 ms, which is under the noise level, so it is perf-neutral.
3. **Some native APIs can replace hand-rolled code** (each needs a correctness check, not a perf bet):
   - `MaterialParameters.Texture.swizzle` replaces the vImage single-channel extraction.
   - `MaterialParameters.Texture.uvIndex` together with the `LowLevelMesh` `.uv1` semantic gives us TEXCOORD_1.
   - `PhysicallyBasedMaterial.textureCoordinateTransform` replaces baking `KHR_texture_transform` into the vertices.
   - `MeshInstancesComponent` (macOS 26) replaces JSON instance expansion.
   - `RealityRenderer.CameraSettings.isToneMappingEnabled` gives explicit tone-mapping control for stills.
4. **Hard RealityKit limits that stay approximations** and must be reported, not hidden:
   - Transmission, volume, iridescence, dispersion and diffuse transmission.
   - Normal-map scale and occlusion strength.
   - Morph normals and tangents.
   - Tone-mapping choice in `RealityView`: `RealityViewRenderingEffects` has no tone-map switch, only `customPostProcessing` and `dynamicRange`.
   - Vertex colours with `PhysicallyBasedMaterial`. These need `ShaderGraphMaterial`, which can be built from in-memory MaterialX via `init(materialXLabel:data:)`.
   - Skinning and morphs can't use `LowLevelMesh`, because it has no joint semantics. That is why we need two mesh paths.
5. **Our recorded performance work (the EXP ledger in `.atelier/backlog.jsonl`) already rules out most "faster texture upload" ideas:**
   - EXP-010: LowLevelTexture swizzle.
   - EXP-015: Metal upload.
   - EXP-018: concurrent async TextureResource.
   - EXP-019: no mipmaps.
   - EXP-022: no compression.
   - EXP-027: lossless.
   - EXP-031: MR 16bpp pack.

   All were rejected. So the simplification should be **perf-neutral deletion**, and new perf work is limited to the few untried candidates flagged below.

## 1. What the current pipeline does, and whether each piece is justified

LOC are from `wc -l` on `main`. Status key:
- **Keep**: justified.
- **Replace**: a native or simpler equivalent exists.
- **Delete**: redundant with GLTFKit2 or another stage.
- **Policy**: a non-spec product heuristic. Keep it only as an explicit, reported option.

| # | Stage / heuristic | Where | LOC | Status | Why |
|---|---|---|---|---|---|
| 1 | Temp-GLB prepare orchestration: gate, fused parse→rewrite→serialize→write, sidecar pack, fallback | `Shared/EntityLoader.swift:130-330` (`prepareGLB`, `applyPrepares`, `packAndPrepareGLTF`, `convertPreparedOrOriginal`) | ~180 | **Delete** | Exists only to feed rows 2–6. It also creates the "prepared produced no mesh → retry original" layer and the stats-JSON-from-prepared-bytes subtlety. |
| 2 | `GLBBox` serialize, `writePrepared`, `appendBytes`, `packSidecar`, `rewriteExtensionLists` | `Shared/GLBBox.swift:75-180,203-221` | ~150 of 289 | **Delete** (keep `peekJSON`/`parseJSON` in GLTFCore) | Only prepare uses it. GLTFKit2 loads sidecar `.gltf` with `assetDirectoryURLKey` directly. |
| 3 | Dequantize and integer→float accessors | `Shared/RealityPrepare.swift:58-98,303-403` | ~150 | **Delete** | GLTFKit2 supports `KHR_mesh_quantization` (its README) and `Packed.floatData` already calls `GLTFTransformPackedDataToFloat` (`Shared/Convert/PackedAccessors.swift:6-13`). The only effect today is to push quantized meshes onto the tight `LowLevelMesh` path. Get the same result by letting the tight path take a `Packed.float*Array` copy when an accessor isn't tight float (see row 10). |
| 4 | WebP → PNG re-encode | `RealityPrepare.swift:99-127,404+` | ~45 | **Delete** (after a fixture test) | GLTFKit2 parses `EXT_texture_webp` into `webpSource` (`impl/GLTFAssetReader.m:728-738`). `gltfImage(for:)` prefers it (`RealityKitResourceContext.swift:236`), and `newCGImage` decodes it with ImageIO (`GLTFAsset.m:704-729`), which reads WebP on macOS 11+. The prepare pass pays for decode, PNG encode and decode again. |
| 5 | `EXT_mesh_gpu_instancing` expansion into JSON clone nodes | `RealityPrepare.swift:128-187,221-260` | ~100 | **Replace** | `GLTFNode.meshInstances` (`GLTFAsset.h:565,612`) plus `MeshInstancesComponent`/`LowLevelInstanceData` (macOS 26, [docs](https://developer.apple.com/documentation/realitykit/meshinstancescomponent)). This is one GPU-instanced draw instead of N entities. Fallback: clone the `ModelEntity` N times at convert (about 15 LOC). |
| 6 | Name unnamed skin joints (JSON) | `RealityPrepare.swift:188-220` | ~35 | **Delete** | `Skin.resolvedName` already does this at convert (`RealityKitConvert+Mesh.swift:13`, `+Animation.swift:45`). |
| 7 | Spec-gloss → metal-rough, with bake gates (≤40 images, ≤24 textured materials, 1024px edge) | `Shared/MetalRoughPrepare.swift` | 388 | **Replace** | `KHR_materials_pbrSpecularGlossiness` is archived, but real files still use it. RealityKit can't invert glossiness (swizzle has no `1-x`), so baking is unavoidable when textured. Move it to convert time on `GLTFMaterial.specularGlossiness` + `CGImage`. EXP-016 (convert-time variant) measured −187 ms, under noise, so it is perf-neutral and removes the GLB rewrite. Drop the image-count gates: fall back to factor-only plus a reported problem. |
| 8 | Seed report / `PreparePipelineReport` | `Shared/PreparePipelineReport.swift` | 66 | **Shrink** | Once prepare is gone, the "what prepare changed" voice folds into `ConvertProblemReport` (e.g. `approximatedSpecGloss`, `decompressedDraco`). One report instead of two. |
| 9 | `GLBTry` NSException guard + "retry without animations" | `Shared/GLBTry.*`, `EntityLoader.swift:393-420` | ~70 | **Keep guard, delete retry** | GLTFKit2 can throw ObjC exceptions, so keep the guard. Convert already try/catches each clip (`RealityKitConvert.swift:98-104`). Run the animation build in its own `GLBTry` *after* the meshes, and a bad clip then can't zero the mesh count. That removes the second convert pass. |
| 10 | Two mesh paths: tight float3 `LowLevelMesh` (EXP-017 KEEP −7.3%) plus `MeshResource.Contents` | `Shared/Convert/RealityKitConvert+Mesh.swift` | 690 | **Keep 2 paths, simplify** | Justified: `LowLevelMesh.VertexSemantic` has no joints or weights, so skinned and morph meshes need `MeshResource.Contents`. Simplify: the static path accepts *any* accessor (memcpy when tight, else `Packed` copy). The fallback is then only skin/morph/points. Drop the memcpy-vs-copy gating that rejects whole meshes. Relative to our own fast path this is perf-neutral; check it on quantized fixtures. |
| 11 | Packed SIMD accessors (EXP-006-v2 KEEP) | `PackedAccessors.swift` | 219 | **Keep** | Measured win. |
| 12 | Material identity cache (EXP-011 KEEP) | `RealityKitResourceContext.swift:108-114` | ~10 | **Keep** | Measured and trivial. |
| 13 | Per-channel vImage extraction → separate `TextureResource` per channel | `RealityKitResourceContext.swift:180-274` | ~60 | **Replace** | `MaterialParameters.Texture.swizzle` ([docs](https://developer.apple.com/documentation/realitykit/materialparameters/texture)) on *one* `.raw`/`.scalar` resource per image. The MR texture becomes 1 upload instead of 2. EXP-031's first cut ("plain swizzle") was a NEAR_MISS at −191 ms; only the 16bpp-pack tweak blew up. So this deletes code at no measured cost. Watch the colour vs scalar semantic when one image feeds both (rare): keep the cache key as (image, semantic). |
| 14 | KTX2/Basis via GLTFKit2 `newTexture` → blit into `LowLevelTexture` with swizzle | `RealityKitResourceContext.swift:150-178` | ~30 | **Keep** (swap swizzle to `Texture.swizzle`) | There's no RealityKit API that decodes BasisU from memory. `TextureResource(contentsOf:)` needs a file, and the KTX2 support there is undocumented. |
| 15 | BLEND heuristics: factor-1 + texture alpha span ≥0.15 → cutout at 0.4 (EXP-009 KEEP, perf); uniform alpha → forced opaque; factor<1 → transparent + separate alpha texture | `RealityKitConvert+Material.swift:196-268`, `Shared/Convert/TextureAlpha.swift` | ~120 | **Split: spec + Policy** | Spec says BLEND means `opacity = factor.a × texture.a`. The spec-correct and simplest mapping is `.transparent(opacity: .init(scale: a, texture: <same base-colour resource, swizzle .alpha>))`. That needs no extra upload, so EXP-009's perf reason (uncached full-res opacity textures) goes away once swizzle reuse lands. "Alpha is uniformly 1 → opaque" is visually spec-equivalent: keep it as an optimization. "Uniform alpha 0 → opaque" and "gradient → cutout 0.4" are **non-spec Sketchfab policy**: keep them behind a named option and always report them. Measure again after swizzle. |
| 16 | Transmission → opacity approximation | `+Material.swift:180-188` | ~10 | **Keep** (hard limit), report | `PhysicallyBasedMaterial` has no transmission ([topics](https://developer.apple.com/documentation/realitykit/physicallybasedmaterial)). |
| 17 | Baked-emissive detection + drop emissive that shares the albedo texture | `Shared/PreviewEmissive.swift`, `+Material.swift:101-120` | ~110 | **Policy** | Non-spec. Move it out of convert into a look/policy step that edits materials after the build, so convert stays spec-pure. Default is the user's call (see open questions). |
| 18 | Studio IBL −2 EV when the file has punctual lights | `PreviewEmissive.studioIBLExponent` | ~5 | **Policy (look layer)** | Not a convert concern. It belongs with lighting. |
| 19 | 4π light scaling (point/spot: candela → lumen) | `RealityKitConvert.swift:204-222` | 3 | **Keep** (verify spot) | Point: glTF candela → RealityKit lumen is ×4π, which is physically right (GLTFKit2 upstream passes the raw value, `GLTFRealityKit.swift:924-946`). For spot lights, RealityKit's lumen-to-cone mapping is undocumented. Keep ×4π, as Filament does, but check it against the Khronos `LightsPunctualLamp` scene. |
| 20 | Skeletal/TRS/morph densify ≤30 fps (EXP-029 KEEP) | `+Animation.swift`, `AnimationHelpers.swift` | 527 | **Keep** | RealityKit has no glTF sampler type, so `SampledAnimation` is required. Measured win. |
| 21 | `KHR_texture_transform` + UDIM tile wrap + V flip, baked into UVs; only the base-colour (or normal) texture's transform/texCoord is honoured | `+Mesh.swift:361-394`, `TextureUV.swift` | ~60 | **Replace** | Use `textureCoordinateTransform` (per material, primary UV) and `secondaryTextureCoordinateTransform` (UV1). Keep a bake only when textures in one material use *different* transforms (rare; report it). `wrapSingleTile` is non-spec: glTF's default sampler is REPEAT (`GLTFAsset.m:1098`), and we pass samplers through, so shifting only changes results when the file asks for CLAMP. **Verify on the CC/UDIM asset with it disabled.** The V flip stays; it's cheap. Whether RealityKit's transform order matches glTF's `T·R·S` with the flip is **unverified**, so test it with `TextureTransformTest`. |
| 22 | POINTS → tiny cross triangles | `+Mesh.swift:245-273` | ~30 | **Keep or delete** | There's no RealityKit point topology. Tiny, but non-spec. Fine to keep and report. |
| 23 | Vertex colours: `.color` written into `LowLevelMesh`; the fallback path drops them | `+Mesh.swift:190-212,570-581` | ~30 | **Unverified** | Forum and WWDC24 guidance says `PhysicallyBasedMaterial` ignores vertex colour and needs a ShaderGraph "Geometry Color" node ([forum 759449](https://developer.apple.com/forums/thread/759449)). **Render `VertexColorTest`**: if the colours are ignored, this code is dead weight today. |
| 24 | Static `lastProblems` / `lastDroppedBakedEmissive` | `RealityKitConvert.swift:51-54` | ~6 | **Replace** | Return a `BuildResult { entity, problems }`. Global mutable state breaks once host, QL and thumbnail share a framework. |
| 25 | Session document built inside convert, plus material thumbs | `+Document.swift` (394), `stampMaterialPreviews` | ~400 | **Move** | The plan already moves the document to GLTFCore (JSON). Only the material thumbs need the texture cache. Expose that as an optional renderer callback. |
| 26 | IBL: HDR → `CGImage` → `EnvironmentResource(equirectangular:)` at runtime, cached per process; key+fill until ready (EXP-002 KEEP) | `Shared/PreviewLighting.swift` | 203 | **Keep** | Runtime prefiltering costs every cold thumbnail process. A bundled prefiltered `.skybox` would skip it, but that's **untested** (see §4). |
| 27 | `StillRenderer` via `RealityRenderer`, readback into a `DeviceRGB` CGImage | `Shared/StillRenderer.swift` | 307 | **Keep, 2 fixes** | Set `cameraSettings.isToneMappingEnabled` explicitly so it matches the live view. Tag the PNG sRGB, not `DeviceRGB` (`StillRenderer.swift:282-290`). The colour-management correctness of that tag is **unverified**. |
| 28 | Unnamed node naming: the entity gets `NodeN` but `bindPath` uses `name ?? ""` | `RealityKitConvert.swift:26-31,124` | — | **Likely bug** | Animations that target unnamed or duplicate-named non-joint nodes probably don't bind. Fix: give each entity a unique name from its node index (display name stays in `GLTFNodeIDComponent`/document) and use the same name in `bindPath`. Also, `nodeIndex(of:)` is O(n) per node (`:196-199`), so O(n²) on large scenes; precompute a map. |

**Net:** deleting rows 1–6 and 8 and replacing rows 7, 13 and 21 removes about **1,100 LOC** of the ~3,000 LOC load path (prepare 388+414, `GLBBox` rewrite ~150, `EntityLoader` ~180, vImage ~60, UV bake ~40). It also removes 2 of the 3 retry layers.

## 2. External reference points

- **GLTFKit2 `GLTFRealityKit.swift`** (upstream `e69e354`, Nov 2025; our `Shared/Convert` is vendored from it). Upstream is simpler and less correct than ours:
  - BLEND is `.transparent(opacity: 1.0)` with a TODO for alpha (`:856-912`).
  - Morphs are TODO; tangents drop `w`; light intensity is passed raw.
  - It uses `MeshResource.Part` only, with no `LowLevelMesh`.

  So it's not a better base to re-vendor. Our fork is the right starting point. Also: GLTFKit2 lists `KHR_materials_variants` as *unsupported* first-class (README), which justifies our `MaterialVariants.swift`.
- **Filament gltfio** ([MaterialProvider.h](https://github.com/google/filament/blob/main/libs/gltfio/include/gltfio/MaterialProvider.h), [ResourceLoader.h](https://github.com/google/filament/blob/main/libs/gltfio/include/gltfio/ResourceLoader.h)). Design ideas worth copying:
  - (a) A material "key" (feature bits plus a per-texture UV index). Our equivalent is a pure `GLTFMaterial → MaterialSpec` mapping function that can be tested without RealityKit.
  - (b) Asset loading (entities) is split from resource loading (textures, async/progressive). For us that would mean first paint with factor-only materials and textures swapped in later. That's **untested**, and it could conflict with a thumbnail needing final pixels.
  - (c) Spec-gloss is handled in the shader. That isn't possible in `PhysicallyBasedMaterial`, hence our bake.
- **Apple APIs confirmed in docs (platform JSON):**
  - `LowLevelMesh` (macOS 15; semantics position/normal/tangent/bitangent/color/uv0–7; any `MTLVertexFormat`).
  - `LowLevelTexture` (macOS 15).
  - `MaterialParameters.Texture.swizzle`/`uvIndex`.
  - `textureCoordinateTransform`/`secondaryTextureCoordinateTransform` (macOS 12).
  - `TextureResource.CreateOptions(semantic:compression:mipmapsMode:)` and async `init(image:withName:options:)` (macOS 15).
  - `MeshInstancesComponent` (macOS 26).
  - `RealityRenderer.CameraSettings.isToneMappingEnabled` (macOS 15).
  - `RealityViewRenderingEffects` { antialiasing, cameraGrain, customPostProcessing, depthOfField, dynamicRange, motionBlur } (no tone mapping).
  - `UnlitMaterial(applyPostProcessToneMap:)`.
  - `ShaderGraphMaterial(materialXLabel:data:)` (macOS 15, in-memory MaterialX, so no bundle resource is needed in the appex).
  - `ModelSortGroupComponent` for explicit transparent draw order.
  - `PhysicallyBasedMaterial.specular` is *additional* dielectric specular ([docs](https://developer.apple.com/documentation/realitykit/physicallybasedmaterial/specular-swift.property)), so our default of `0` when `KHR_materials_specular` is absent is correct. Mapping `specularFactor` onto it is only an approximation.
- **WWDC25 "What's new in RealityKit"** ([287](https://developer.apple.com/videos/play/wwdc2025/287/)): `MeshInstancesComponent`, `Entity(from: Data)`, AVIF textures, `customPostProcessing` on macOS. No glTF import.

## 3. Performance notes (what's measured vs what's open)

- **Measured and settled.** Don't re-bench these without a new asset class:
  - Texture upload variants: EXP-010, 015, 018, 019, 022, 027, 030, 031, 032.
  - Accessor/index micro-paths: EXP-013, 014, 020, 021, 024, 028.

  AGENTS.md already records that the residual wall is `TextureResource` generation on large rasters.
- **Untried, likely high value, needs measurement:**
  1. **Thumbnail-only texture cap.** Decode with `CGImageSourceCreateThumbnailAtIndex` (max edge ~1024) in `loadThumbnail`. A 512 px Finder icon can't show 4K texel detail. This directly attacks the measured residual wall *and* peak memory in the thumbnail extension. The extension memory ceiling is **not documented**; measure the footprint on corpus 09/10 (`footprint`, or Instruments Allocations under `QLThumbnailGenerator`).
  2. **Decode `CGImage`s off the main actor before the MainActor hop** (ImageIO decode is thread-safe). Today `cachedCGImage` decodes inside the MainActor convert (`RealityKitResourceContext.swift:241-251`), which blocks the host UI during load. EXP-018 parallelized `TextureResource` creation, not decode, so this is different. Gate: host "open ready" time, plus main-thread hang time in Instruments.
  3. **Prefiltered IBL.** `EnvironmentResource(cube:)` or a `.skybox` bundle asset for the three catalog HDRs versus runtime equirect prefilter. EXP-002 showed IBL is on the cold path (~658 ms in the WebKit bench; RealityKit is unmeasured).
- **Memory:** the per-convert `CGImage` cache keeps every decoded RGBA raster alive until convert ends, and longer in the host for material thumbnails. EXP-032 (evict after upload) was rejected on *time*; memory was never measured. Pair it with item 1.

## 4. Recommended target architecture for `RendererRealityKit`

```text
GLTFCore (JSON: document, stats, dims, variants, validator)
   │
RendererRealityKit
   Load      GLTFAsset(url, assetDirectory) off-main; Draco/meshopt/KTX2/WebP/quantization by GLTFKit2
             variant apply · animation filter · optional off-main image decode (thumbnail: capped)
   Build     @MainActor SceneBuilder → BuildResult { entity, problems }
               NodeBuilder   transform, unique index-names, lights (×4π), cameras, instancing (MeshInstancesComponent)
               MeshBuilder   static → LowLevelMesh (any accessor); skinned/morph/points → MeshResource.Contents
               MaterialMap   pure GLTFMaterial → spec struct (testable) → PBR/Unlit; swizzle, uvIndex, uv transform,
                             spec-gloss bake (convert-time), identity cache
               TextureCache  (image, semantic) → TextureResource; KTX2 → LowLevelTexture
               AnimationBuilder  SampledAnimation ≤30 fps, own GLBTry
   Policy    optional, reported: Sketchfab BLEND fixups, baked-emissive drop  (post-build material edits)
   Stage     look (IBL/key+fill, −2 EV rule), camera, floor, overlays
   Surface   RealityKitCanvas(session:) · commands (FocusedPreviewCommands) · renderStill(url:size:look:) · features
```

Public API (matches the plan's Approach):
- `struct RealityKitCanvas: View`: binds `PreviewSession`, registers the commands object.
- `static func renderStill(url: URL, size: CGSize, look: Look) async throws -> CGImage`: load (thumbnail mode), build, then `RealityRenderer`.
- `static let features: Set<RendererFeature>`: advertise playback, morphs, skins, variants, hide/solo, KTX2, Draco, meshopt. Mark transmission/volume/iridescence/tone-map choice as unsupported, so `DerivedAvailability` never offers them.
- Internal: `BuildResult`, `ConvertProblemReport` (now including the former prepare flags).

### Delete / keep / replace, ranked by value/risk (do them in this order)

| Rank | Action | Value | Risk | Proof |
|---|---|---|---|---|
| 1 | **Delete** WebP→PNG and joint-naming prepare (rows 4, 6) | Low-medium LOC, removes one decode/encode | Low | WebP fixture + unnamed-joint fixture render the same PNG (`StillRenderProofTests`) |
| 2 | **Delete** dequantize by widening the tight `LowLevelMesh` path to `Packed` copies (rows 3, 10) | ~150 LOC | Low-medium | Quantized Khronos samples (e.g. `MeshQuantization`-style) pixel-diff; corpus load bench within noise |
| 3 | **Replace** instancing expansion with `MeshInstancesComponent` (or clones) from `GLTFNode.meshInstances` (row 5) | ~100 LOC, fewer entities | Medium (new API; selection/picking of instances) | `SimpleInstancing` sample pixel-diff; hide/solo still works |
| 4 | **Replace** spec-gloss GLB rewrite with a convert-time bake (row 7) → **then delete the temp-GLB machinery** (rows 1, 2, 8) | ~550 LOC, removes the retry layer and temp files | Medium | `SpecGlossVsMetalRough` pixel-diff; sidecar `.gltf` tests go through GLTFKit2 directly |
| 5 | **Replace** vImage channel split with `Texture.swizzle`; opacity from the base-colour resource with an alpha swizzle; split BLEND into spec + policy (rows 13, 15) | ~150 LOC, spec-correct BLEND | Medium (EXP-009 perf reason must stay gone) | `AlphaBlendModeTest` pixel-diff; corpus bench within noise |
| 6 | **Replace** the animation retry with an isolated animation `GLBTry`; return `BuildResult` instead of statics (rows 9, 24) | Clarity and correctness across targets | Low | Existing Draco+skin+anim fixtures |
| 7 | **Fix** unnamed-node bind paths and O(n²) `nodeIndex` (row 28) | Correctness | Low | `AnimatedTriangle`-style fixture with an unnamed node |
| 8 | **Replace** UV bake with `textureCoordinateTransform` + `uvIndex`; check `wrapSingleTile` (row 21) | Spec coverage (TEXCOORD_1, per-material transform) | Medium (transform-order and V-flip semantics unverified) | `TextureTransformTest`, `MultiUVTest` |
| 9 | **Move** emissive/IBL heuristics to a Policy/Look step (rows 17, 18) | Keeps convert spec-pure | Low (behaviour unchanged if defaults kept) | `EmissiveBoostTests` |
| 10 | **Measure first:** thumbnail texture cap, off-main decode, prefiltered IBL (§3) | Possibly large first-frame/memory wins | Adds some code | Corpus bench + footprint; only KEEP beyond noise |
| — | **Keep as is:** Packed accessors, material cache, ≤30 fps densify, KTX2 `LowLevelTexture`, `RealityRenderer` stills, IBL-after-first-frame, `GLBTry`, variants, 4π point scaling | Measured or required | — | — |

## Unresolved (need measurement or a decision, not assertion)

1. Does `PhysicallyBasedMaterial` use the `LowLevelMesh` `.color` attribute? Render `VertexColorTest`. If it doesn't, vertex colours need one small MaterialX `ShaderGraphMaterial` (a new dependency on MaterialX authoring) or stay reported as unsupported.
2. Does `textureCoordinateTransform` compose in the same order as glTF `T·R·S` once the V flip is applied? Check with `TextureTransformTest`.
3. Is `wrapSingleTile` still needed now that samplers are passed through with REPEAT as the default?
4. Spot-light intensity scaling: compare against a reference render.
5. Thumbnail-extension memory ceiling and our peak footprint. Not documented; measure it.
6. Policy defaults (Sketchfab BLEND fixups, baked-emissive drop, −2 EV): the product owner decides spec-first vs Sketchfab-friendly. Recommendation: keep today's defaults and label them in the report UI.
7. Tone mapping: `RealityView` has no switch. Whether `customPostProcessing` runs before or after RealityKit's tone map is undocumented, so cross-renderer tone calibration stays out of scope, as the plan says.
8. `MeshInstancesComponent` and selection: can one instance be hit-tested and hidden separately? If per-instance hide/solo is needed, use cloned entities instead.
