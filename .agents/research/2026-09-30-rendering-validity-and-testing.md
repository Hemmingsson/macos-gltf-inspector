# Rendering validity and how to prove it (RealityKit + WebKit over GLTFCore)

Date: 2026-09-30 · Scope: research only · Inputs: `main` @ `a4a4a2f`, `.worktrees/webkit-renderer` @ `fa7dd64` plus its uncommitted tree (read only) · Plan: `.agents/plans/2026-09-30-renderer-separation.md`

## Answer

1. **"Valid rendering" has two layers.** The first is a **valid file**. The official Khronos validator is already embedded and is the latest npm release. Keep it in core. The second is a **correct interpretation** of the file. Only images show this, and the best proof is **self-checking Khronos test assets**. On those assets one part of the picture must match another part of the same picture, so the assertion is true for any renderer. Per-renderer goldens only catch *regressions*, not correctness.
2. **Never compare pixels across the two renderers as a pass/fail gate.** RealityKit uses its own system tone mapper and photometric light scale. The Khronos renderer uses PBR Neutral with unitless intensities. Give each renderer its own goldens. Use the **same manifest** (camera pose, fully pinned look) and the **same metric**. A cross-renderer side-by-side is an informational report only, the same way the Khronos Render Fidelity site uses one.
3. **The look belongs in core, in scene-referred terms.** Fields: `exposureEV` (scales *all* scene radiance before tone mapping), `environmentIntensity` (linear), `environmentYawDegrees` (relative to one documented canonical orientation), `toneMapping`, `background`, `lightSource` policy. Each renderer owns a small, documented mapping with **measured constants** (yaw offset, photometric scale). Today two mappings disagree. The web goldens bake in an environment yaw that the app does not ship. On RealityKit, exposure moves only the IBL.
4. **Keep complexity low.** Use one manifest file for both renderers, one static capability set per renderer that decides which entries run, and one comparator (the existing `PixelDiff`). Add FLIP only as an optional report.

## 1. External references (verified)

| Topic | What it says | Consequence for us |
| --- | --- | --- |
| glTF 2.0 core ([spec](https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html)) | Right-handed, +Y up, "the front of a glTF asset faces +Z". Linear distances are in meters. Appendix B (BRDF) is **informative**: metal/dielectric fresnel mix, GGX, Smith, Lambert. baseColor and emissive textures use the sRGB transfer function; metallicRoughness, normal and occlusion are linear. The spec says nothing about tone mapping or exposure. | Viewer choices (tone mapping, exposure, IBL) are *ours* to define and document. The spec cannot judge them. |
| [KHR_lights_punctual](https://github.com/KhronosGroup/glTF/blob/main/extensions/2.0/Khronos/KHR_lights_punctual/README.md) | Point/spot intensity is in **candela** (lm/sr). Directional is in **lux**. The range falloff is a recommended smooth window divided by d². | RealityKit point/spot `intensity` is in **lumens** and directional is in **lux** ([Apple PointLightComponent.intensity](https://developer.apple.com/documentation/realitykit/pointlightcomponent/intensity), [DirectionalLightComponent.intensity](https://developer.apple.com/documentation/realitykit/directionallightcomponent/intensity)). For an isotropic point, cd·4π = lm, so the point conversion is right. The spot conversion is *unverified*: glTF candela is on-axis intensity, and Apple does not say how RealityKit spreads spot lumens over the cone. |
| RealityKit defaults (Apple doc JSON) | Point default 26 963.76 lm (= 2 145.7 cd · 4π). Spot default 6 740.94 lm (= point/4). Directional default 2 145.7 lux. | The spot default is not the point default, which suggests a cone-dependent convention. **Measure it.** |
| [Khronos PBR Neutral](https://github.com/KhronosGroup/ToneMapping/tree/main/PBR_Neutral) | Input is linear Rec.709. Output is linear [0,1] followed by the sRGB OETF. Kₛ = 0.76, K_d = 0.15. No hue shifts. Analytically invertible. | Pure math. It can be implemented and unit-tested in core. |
| RealityKit tone mapping | `RealityViewRenderingEffects` (macOS 15+): `dynamicRange`, `customPostProcessing` ([doc](https://developer.apple.com/documentation/realitykit/realityviewrenderingeffects)). The **`RealityRenderer.CameraSettings.isToneMappingEnabled`** flag also exists on macOS 15+. | The offscreen `StillRenderer` could render with tone mapping turned off and apply exposure plus PBR Neutral itself, which would give an apples-to-apples still. For the live view, this is only possible through `customPostProcessing` (not verified). |
| [KHR_node_visibility](https://github.com/KhronosGroup/glTF/blob/main/extensions/2.0/Khronos/KHR_node_visibility/README.md) | Ratified. `visible` defaults to true and must be true on all ancestors. Lights on hidden nodes are hidden. Cameras are not affected. | This is a capability. Test assets exist: `NodeVisibilityTest`, `CubeVisibility`, `LightVisibility`. |
| Khronos Sample Renderer (vendored `gltf-viewer.module.js`) | Defaults: **`environmentRotation: 90`**, `exposure: 1` (linear), `iblIntensity: 1`, `usePunctual: true`, tone map enum includes `KHR_PBR_NEUTRAL`, key light 1 and fill 0.5. The `u_Exposure` uniform multiplies radiance before the tone map. | "Khronos default look" = 90° environment yaw. Anything that sends 0 renders a different look. |
| [glTF-Validator](https://github.com/KhronosGroup/glTF-Validator) | npm `latest` is **2.0.0-dev.3.10** (2024-10-22), and that is exactly what `Vendor/gltf-validator/README.md` vendors. | Keep embedding it; no upgrade exists. It probably predates newer extensions such as `KHR_node_visibility` and will report them as unsupported (info, not error). This is an assumption: run it on `NodeVisibilityTest` to confirm. |
| [glTF-Sample-Assets](https://github.com/KhronosGroup/glTF-Sample-Assets) | Lists: `Models-showcase.md`, `Models-testing.md` ("for testing of viewers"), `Models-core.md`, `Models-pbrtest.md`, and the `Compare*` series. Several are **self-checking**: TextureEncodingTest (4 columns must match; embedded gamma/ICC must be ignored), PointLightIntensityTest (R+G+B = White), TextureSettingsTest, TextureTransformTest, OrientationTest, NegativeScaleTest. | These are correctness oracles that need no reference renderer. |
| [glTF Render Fidelity](https://github.khronos.org/glTF-Render-Fidelity/) and [model-viewer render-fidelity-tools](https://github.com/google/model-viewer/tree/master/packages/render-fidelity-tools) | Side-by-side comparison of the same sample assets across renderers (three.js, Babylon, model-viewer, path tracer). The model-viewer config gives each scenario a model, HDR, orbit, dimensions and a per-renderer `exclude` list. | Good template: one scenario manifest plus per-renderer exclusions. Comparison is visual, not a gate. |
| Peer test harnesses | three.js e2e: pixelmatch with `pixelThreshold 0.1`, `maxDifferentPixels 0.1%`, and a long exclude list ([puppeteer.js](https://github.com/mrdoob/three.js/blob/dev/test/e2e/puppeteer.js)). Babylon: per-test `errorRatio` override (values 0.1–7.5 %, [config.json](https://github.com/BabylonJS/Babylon.js/blob/master/packages/tools/tests/test/visualization/config.json)). Filament renderdiff: goldens in a separate repo, keyed by platform and backend, rendered headless with Mesa ([README](https://github.com/google/filament/tree/main/test/renderdiff)). [NVIDIA FLIP](https://github.com/NVlabs/flip): perceptual mean error in 0..1 (`pip install flip-evaluator`). | Norms: goldens are per backend, there is a global tolerance plus a rare per-test override, and there is an explicit exclude or capability list. Our `PixelDiff` already matches this. |

## 2. Our repo today: what exists and the gaps

**What exists (good):**
- Official validator in JavaScriptCore with a size guard: `Shared/GLTFValidator.swift:61-70`. It is called after first paint (`GLTFInspector/HostShellRootView.swift:453`).
- A well-designed web pixel harness. It uses mean absolute error 2.0/255, a bad-pixel delta of 24 and a bad-pixel fraction of 0.5 % (`.worktrees/webkit-renderer/GLTFInspectorTests/PixelDiff.swift:69-73`). It has self-tests for the comparator, and each manifest entry records a camera pose (`TestModels/References/manifest.json`). It fails when samples are missing (`TestModels/References/README.md`).
- Pinned sample fetch: `scripts/fetch-test-models.sh:11`, 12 GLBs. Only 1–2 of them are self-checking test assets.

**Gaps:**

| # | Gap | Evidence |
| --- | --- | --- |
| G1 | **The web goldens use environment yaw 90° (renderer default); the app ships 0°.** The harness never sends a rotation or an exposure. `WebPreviewCanvas` sends `environmentRotation: 0` on its first update because `previous == nil`. The manifest records environment and tone map, but not rotation or exposure. | `PixelDiffReferences.swift:144-149`; `WebPreviewCanvas.swift:53, 219-222`; module default `environmentRotation:90` |
| G2 | **Exposure means different things.** Web multiplies all radiance by 2^EV before the tone map (`viewer.html:593`). RealityKit adds EV to the IBL `intensityExponent` only, so punctual lights and emissive are unaffected. | `Shared/PreviewEmissive.swift:67-68`; `Shared/PreviewLighting.swift:124` |
| G3 | **Tone mapping differs.** Web uses PBR Neutral. RealityKit uses its system tone map; the setting is not wired. `StillRenderer` renders to `bgra8Unorm` with the default tone map. | `Shared/StillRenderer.swift:163-164, 190`; `viewer.html:56` |
| G4 | **The file-lights policy is RealityKit-only.** RealityKit dims the studio IBL by −2 EV when the file has lights. Web keeps `usePunctual` and `iblIntensity` at their defaults, with no dimming. | `PreviewEmissive.swift:10, 62-68`; no match in the web tree |
| G5 | **The no-IBL fallback lights differ in direction and scale.** RealityKit uses key 2 500 lux and fill 900 lux. Khronos uses key 1 and fill 0.5 in its own directions. Neither is part of the look model. | `PreviewLighting.swift:70-71`; module `lightKey`/`lightFill` |
| G6 | **Light units are only half verified.** Point cd→lm ·4π is correct and directional lux→lux is correct (`Shared/Convert/RealityKitConvert.swift:218, 228, 235`). Spot ·4π is unverified. The balance between RealityKit's photometric scale and the IBL radiance is unmeasured. | Apple defaults above |
| G7 | **RealityKit has no image assertion.** The proof only checks PNG size > 800 bytes. Khronos-sample tests *skip* when samples are missing, while the web harness *fails*. | `StillRenderProofTests.swift:37, 80`; `KhronosSampleTests.swift:8, 23` |
| G8 | **No capability list.** The RealityKit gaps exist only as `ConvertProblemReport.ignoredExtensions`, so nothing drives which tests run. | `Shared/ConvertProblemReport.swift:34-40` |
| G9 | **The validator is not run over the sample corpus.** Only one invalid fixture and the cube are tested. | `GLTFInspectorTests/GLTFValidatorTests.swift:6-23` |
| G10 | **The look is split and has no units.** `AppLook` (env on/off, catalog, custom), `LightingSettings` (EV, yaw degrees, two booleans), `RendererLookDefaults` (duplicated keys), and `WebPreviewCanvas.Look`. The canonical yaw is never defined. | `Shared/AppLook.swift:19-28`; `PreviewUI/Seam/Models.swift:806-822`; `RendererLookDefaults.swift:17-23` (already in the plan) |

## 3. Recommendation

### 3a. Look definition in core (one value type, units stated)

```swift
public struct RenderLook: Codable, Equatable, Sendable {
    public var environment: EnvironmentRef?      // catalog id or custom file; nil = core-defined key+fill rig
    public var environmentIntensity: Double = 1  // linear multiplier on HDR radiance (file-light dimming = 0.25)
    public var environmentYawDegrees: Double = 0 // 0 = canonical orientation (below), +CCW seen from +Y
    public var exposureEV: Double = 0            // camera exposure: ALL scene radiance × 2^EV before tone map
    public var toneMapping: ToneMapping = .pbrNeutral // .pbrNeutral | .none (add others only on demand)
    public var background: Background
    public var lights: LightSource = .studio     // .studio | .file | .both — policy, not intensity
}
```

- **Canonical orientation:** define yaw 0 as "what the Khronos Sample Viewer shows by default". Web mapping: `environmentRotation = yaw + 90`. RealityKit: `yaw + rkYawOffset`, which must be measured. This choice keeps our web renders comparable with Khronos screenshots and the Render Fidelity site.
- **The fallback rig (key+fill) is data in core:** directions in glTF space and intensities in lux. Each renderer converts them the same way it converts file lights.
- **Per-renderer mapping lives in one file per framework** (`RenderLook+WebKit.swift`, `RenderLook+RealityKit.swift`). Each file has a header table listing field, target parameter, formula and a note saying whether the value is measured or assumed. RealityKit exposure should be exact in `StillRenderer`: turn tone mapping off, use a float target, then apply core's `ToneMap.apply(exposureEV:mode:)`. In the live view it stays an approximation (IBL exponent, plus scaling punctual lights by 2^EV) until `customPostProcessing` is proven. Declare this as a capability (`exposureScope: .all | .iblOnly`) instead of hiding it.

### 3b. Test strategy (four layers, cheapest first)

1. **Core, no GPU (renderer-agnostic, always runs):**
   - Validator over every fixture and every fetched sample. Expect 0 errors; the `invalid/` and `corrupt/` fixtures expect specific codes.
   - JSON-derived stats, dimensions, variant names and visibility on known assets.
   - `RenderLook` math: EV→linear, PBR Neutral against reference values from the Khronos repo (and its invertibility), yaw normalisation, cd→lm and lux conversions, and the file-light dimming policy.
   - Manifest and capability consistency: every manifest entry's `requires` is a known feature, and every renderer either runs it or lists a reason.
2. **Renderer structural, no pixels:**
   - RealityKit: the existing entity assertions.
   - Web: the page's `gatherStatistics` must equal the core `PreviewStats` for each sample. This is a cheap cross-renderer agreement check with no tolerance.
3. **Per-renderer goldens**, one shared manifest and `PixelDiff` for both. The manifest gains `look` (all `RenderLook` fields pinned, including yaw and EV) and `requires: [feature]` per entry. Goldens live at `TestModels/References/<renderer>/…`. A per-entry `tolerance` override is allowed but must be justified in the manifest, as Babylon does. The RealityKit goldens use `StillRenderer` at a fixed pose. Missing samples fail; they do not skip (G7).
4. **Oracle checks (correctness, not regression), phase 2:** manifest-declared rectangular regions in the rendered golden pose that must match each other within ΔE or MAE:
   - TextureEncodingTest: the columns match.
   - PointLightIntensityTest: R+G+B equals White.
   - TextureSettingsTest.
   - OrientationTest.
   - A NodeVisibilityTest pair: the hidden-state render equals the render without that node.

   The same assertion runs on both renderers. This is the only layer that proves "valid rendering" rather than "unchanged rendering".
5. **Informational:** `scripts/render-report.sh` writes the RealityKit and web renders side by side plus a FLIP mean for each sample into `/tmp`. It never gates.

**Capability set:** `static let features: Set<RenderFeature>` on each renderer. Cases: extension names, `.toneMapPBRNeutral`, `.exposureAll`, `.envRotation`, `.nodeVisibility`, `.morph`, `.skin`, `.variants`, `.transmission`, and so on. The RealityKit set is derived from (and tested against) `ConvertProblemReport.ignoredExtensions` so there is one source of truth. The test runner filters manifest entries with `requires ⊆ features`. For a filtered-out entry it asserts that the renderer *reports* the gap, for example as a convert problem. This is the same set the plan already feeds into `DerivedAvailability`.

**Sample set (about 16; pin the SHA, extend `fetch-test-models.sh`):**
- Correctness oracles: TextureEncodingTest, PointLightIntensityTest, TextureSettingsTest, TextureTransformTest, OrientationTest, NegativeScaleTest.
- BRDF and IBL: MetalRoughSpheresNoTextures, EnvironmentTest.
- Other features: AlphaBlendModeTest, NormalTangentMirrorTest, VertexColorTest, EmissiveStrengthTest, ClearCoatTest, NodeVisibilityTest, DirectionalLight or LightsPunctualLamp, plus one showcase model (BoomBox or DamagedHelmet).
- Candidates to drop (redundant for correctness): BarramundiFish, Avocado, BoxInterleaved.
- Add Compare\* assets only when a material extension becomes a capability.

### 3c. Keeping it low-complexity

- There is one manifest, one comparator (`PixelDiff`, moved to a shared test helper), one capability set per renderer, and one `RenderLook`. Do not add a registry, a golden server or a cross-renderer pixel gate.
- FLIP stays optional in a shell script. The Swift gate stays MAE plus bad-pixel fraction, which is already in the same range as three.js and Babylon.
- Oracle regions are plain rectangles stored in the manifest, and they come after goldens exist.

## 4. Needs measurement (do before calibrating goldens)

1. **RealityKit yaw offset.** Build a synthetic equirect HDR with a distinct colour per ±X/±Z quadrant (tiny script in `assets/scripts/`, per the asset-tooling rule). Render a mirror sphere on both renderers at yaw 0 and record which colour faces +Z. Expected: web shows the Khronos convention at 90°, and RealityKit is off by some multiple of 90°. This is an assumption to verify.
2. **RealityKit photometric scale `k`.** Render a white Lambert plane lit by a directional light only (no IBL), with tone mapping disabled (`isToneMappingEnabled = false`) and a float target. Find `k` such that RealityKit lux L matches Khronos intensity L/k. Then check the spot mapping on-axis against a point light of the same candela.
3. **`StillRenderer` with tone mapping off:** check whether the output is scene-linear, and whether the sRGB encode is applied to a float target.
4. **Live `customPostProcessing`:** check whether its source texture is pre- or post-tone-map. This decides whether live RealityKit can honour PBR Neutral and full-scene exposure.
5. **Validator on newer extensions:** run it on NodeVisibilityTest and AnimationPointerUVs and check that it reports info, not errors.
6. **Golden stability across runs:** measure the real noise floor on this machine by rendering 10 times. It is unknown for RealityKit MSAA and for web. Set the tolerance from that, not from a guess.

## Unresolved

- Pick the canonical orientation: the Khronos default (recommended) or RealityKit's native orientation. It changes every web golden once, because of G1.
- Whether RealityKit should ship PBR Neutral for stills only, which makes thumbnails and the live view differ, or stay on the system tone map everywhere, where the capability says `.toneMapPBRNeutral = false`.
