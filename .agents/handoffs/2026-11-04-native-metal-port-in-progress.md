# Finish the native Khronos → Metal port

This handoff resumes a working but incomplete hand port of the pinned Khronos renderer.
**Do not declare the port finished or switch the default renderer yet.** The original 21
Khronos references passed unchanged; the expanded 33-sample suite exposed additional gaps.
The user explicitly requested this handoff instead of continuing implementation in this chat.

Snapshot: **2026-11-04**, `/Users/mattias/dev/glb-preview`, branch `main`, HEAD `9ab1ed8`
when recorded. Other work is happening in the same checkout; recheck HEAD and status.
All native-port changes are **uncommitted**. Backlog task **`hc7w6r13`** is started, not complete.

> **Update (2026-11-04, later session): strict parity is green — all 33 manifest samples pass**
> the unchanged comparator (evidence: [33-sample results](2026-11-04-native-metal-verification-33.txt)).
> Sections "Fix these next" 1–3 are done; 4 (controls) and 5 (measure, cut over) remain. Fixes:
>
> - **Meshopt:** `RendererMetal/Scene/MetalMeshoptPreprocessor.swift` decodes `KHR_`/`EXT_meshopt_compression`
>   bufferViews with vendored official meshoptimizer v1.2 decoders (`Vendor/meshoptimizer/`, via
>   `MetalMeshopt.{h,cpp}`; COLOR filter + codec v1) and hands GLTFKit2 an in-memory GLB. External
>   buffers and images are folded into its BIN chunk, because GLTFKit2 resolves files against `asset.url`,
>   which is nil for data-loaded assets.
> - **KTX2:** `MetalKTX2.{h,c}` calls libktx (headers vendored in `Vendor/libktx/include`, v4.2.1;
>   symbols come from the pinned GLTFKit2 binary) and transcodes every Basis payload to ASTC 4×4, the
>   page's first choice, using the file's transfer function for sRGB. GLTFKit2's own path picked ETC for
>   ETC1S and left the mip levels it generates uninitialised. The page uses libktx 4.4.0; parity passes anyway.
> - **Generated tangents:** the page negates `w` of every MikkTSpace tangent (`MetalTangents.c`). This fixed
>   CompareSheen and CompareAnisotropy.
> - **Transmission texture:** GLTFKit2 0.5.15 always drops `KHR_materials_transmission.transmissionTexture`
>   (it tests its own empty params). The loader reads it from the source JSON (`authoredTransmissionTexture`).
>   This fixed CompareIor and CompareDispersion.
> - **Transmission sampler:** the page's opaque texture uses NEAREST magnification and LINEAR_MIPMAP_LINEAR
>   minification, so roughness-0 glass samples mip 0 nearest. With this fix the native `transmissionSampler`
>   passes ChronographWatchWebP, and CompareVolume's bad pixels drop from 0.094% to 0.005%.
> - The unused prepass environment shader entry was removed.
>
> - **Draw order (later):** `MetalDrawLists` in `MetalRenderer.swift` ports `prepareScene` grouping
>   (opaque instancing groups; transmission by extension presence) and `sortPrimitivesByDepth`
>   (indexed-centroid view Z, ascending, stable, re-sorted in place per frame). Main pass: opaque →
>   transmission → transparent, both filtered to depth ≤ 0; prepass: opaque → all transparent.
>   Prepass clears to the page's `[0,0,0,0]`; unlit prepass draws write `toneMapInverse`.
>   Pixel numbers unchanged on all 33; `MetalDrawOrderTests` covers the order.
>
> Still open from the notes below: the derivative-tangent path for
> primitives without NORMAL, all control/overlay verification, bench, the three surfaces, cutover.
> `./scripts/dev.sh test` had one failure, which the port did not cause: `GLTFValidatorCorpusTests`
> reports `ui-showcase.glb: SKIN_SKELETON_INVALID`. Neither that fixture nor the validator has
> uncommitted changes.

## Start here

1. Read [the approved plan](../plans/2026-11-04-native-metal-khronos-renderer.md),
   [the research](../research/2026-11-04-metal-khronos-port.md), and project `AGENTS.md`.
2. Read the verification results below. Native rendering already works; do not restart it.
3. Run the strict Metal suite, repair remaining material/compression differences, then verify
   controls, surfaces and performance before replacing Filament.

```bash
cd /Users/mattias/dev/glb-preview
./scripts/fetch-test-models.sh
TEST_RUNNER_GLTF_METAL_PARITY=1 ./scripts/dev.sh test \
  -only-testing:GLTFInspectorTests/MetalCameraTests \
  -only-testing:GLTFInspectorTests/MetalSceneLoaderTests \
  -only-testing:GLTFInspectorTests/PixelDiffMetalTests
```

Success means all **33** manifest samples pass the existing comparator, without changing
old PNGs or tolerances. Failures write actual/expected/diff PNGs to
`/tmp/GLTFInspector-pixel-diff/`. Inspect them.

The latest invocation of that command was started for handoff, with output redirected to
`/tmp/metal-handoff-verification.log`. Its final result is recorded at the end of this file.

## User intent and constraints

The user asked to hand-port Khronos to Metal, use parallel subagents efficiently, run tests,
and keep going until it works instead of Google Filament. They then asked for a handoff so
another agent can finalize it. Do not ask again whether to start the already-authorized port.

- Hand-written MSL from Khronos **863b981**, never GPL MeshEditor code or a generated
  SPIR-V renderer. Preserve fidelity before changing the default.
- Keep all three surfaces together: document window, Quick Look, Finder thumbnail.
- `GLTF_RENDERER=metal` selects the native host across the existing shared host factory.
  **Default remains Filament.** `GLTF_RENDERER=webkit` retains the oracle.
- The dev-only second-backend exception is already approved in `AGENTS.md`.
- Bind/rest pose only. Do not add playback or user renderer settings.
- Do not launch/activate the app or run XCUITest without satisfying project/skill rules.
  No app installation, real-window verification, or XCUITest was done in this session.
- Preserve unrelated work. UI edits present at session start were subsequently committed by
  another actor. At handoff `docs/README.md` and `docs/pipeline-web-renderer.md` were deleted
  by other work; this port did not delete them. Do not restore/revert them casually.

Parallel work was split into shaders, loader, and camera/tests; the parent did GPU encoding,
IBL integration and host integration. All three subagents eventually hit an account usage
limit. Their changes were integrated and subsequently corrected by the parent. Their agent
turns are not pending implementation to wait for.

## What is implemented

| Path | State and purpose |
| --- | --- |
| `RendererMetal/MetalRenderer.swift` | Extension-safe native renderer. Build-time default.metallib; linear RGBA16F + R8UI tonemap flags, depth, tone pass, RGBA8 straight-alpha sRGB CGImage readback; transmission prepass at 1024² RGBA8 4×MSAA + generated mips. Native presentation copies through a fullscreen shader into CAMetalLayer, without image readback. |
| `RendererMetal/Shaders/` | Hand MSL core PBR, GGX, sheen, iridescence, anisotropy, IOR/specular, clearcoat, transmission/volume/dispersion and diffuse-transmission paths; extension texture maps in argument buffer; tone curves; IBL compute kernels. Not all paths have passed parity. |
| `RendererMetal/Shaders/ShaderTypes.metalh` | GPU ABI. The `.metalh` suffix deliberately avoids inclusion in the Objective-C umbrella. |
| `RendererMetal/MetalMaterialUniforms.swift` | Swift ABI and cached per-draw material argument buffers. Twenty texture maps with individual samplers, UV sets and transforms. |
| `RendererMetal/Scene/` | GLTFKit2 loader in detached work, parallel image decode, packed vertices and indices, selected scenes, variants, visibility, punctual lights, CPU morph/skin rest pose and instancing. Material extension factors and textures are mapped. |
| `RendererMetal/Draco/` | Restored shipped Objective-C++ Draco plugin. BoxDraco loads and matches. |
| `RendererMetal/Scene/MetalTangents.{h,c}` | Mikk wrapper with 80-byte vertex callbacks; loader deindexes corners to preserve tangent splits. |
| `Vendor/mikktspace/` | Official C source, license and pinned VERSION/hash. |
| `RendererMetal/MetalCamera.swift` | Camera pose replay, perspective/ortho; Metal projection tests and GL projection used for the actual vertex depth remap. |
| `RendererMetal/MetalEnvironment.swift` | Reads exact prefiltered Khronos cubemaps and LUTs from compressed binary assets; no runtime WebKit or shader-source compilation. |
| `assets/ibl/khronos/*.metalibl` | Three environments plus one shared LUT file. LZFSE compressed binary plists, about 14 MB total after deduplication, reduced from about 100 MB. |
| `RendererWebKit/KhronosMetalRendererHost.swift` | Host seam adapter, CAMetalLayer view, orbit/pan/dolly, fit, variants/scenes, still PNG, debug/wireframe, on-demand redraw; display link only while auto-rotating. Not real-window verified. |
| `RendererMetal/MetalOverlays.swift` | Last-minute floor/origin/selected-subtree AABB line overlays. Needs behavior and visual verification. |
| `RendererMetal/Scene/MetalScene.swift` | Last-minute file-camera matrices and subtree bounds in addition to scene/draw structures. Needs behavior verification. |
| `project.yml` | RendererMetal target, extension-safe settings, exact GLTFKit2 0.5.15 + DracoSwift 1.5.7, Metal links/embedding, Mikk sources, test dependency, MTL_FAST_MATH=NO. |

`RendererMetal/RendererMetal.h` must remain the umbrella importing the Draco/Mikk headers.
Without it Xcode generated a Swift-only module map and Swift could not see
`GLTFMetalGenerateTangents` despite the header being public.

The host must directly carry the GLTFKit2 package dependency. A framework target did not embed
it, causing a launch-time dyld error. Use the package dependency without `embed: true`:
XcodeGen's explicit package embed flag attempted to copy a nonexistent `GLTFKit2-product`.
Draco is linked by the native framework.

## Verification already completed

### Original 21-sample parity passed

`/tmp/metal-gpu7.log` is the successful strict run before expanding the manifest.
Every original sample passed the unchanged tolerance (mean ≤1/255; bad pixels ≤0.1%).
Examples: AnimatedMorphCube and InterpolationTest exact; most models max delta 1–5;
BoomBox mean 0.001, one pixel over16; LightsPunctualLamp mean 0.023, max15;
ClearCoatTest mean0.017, 16 pixels over16. Do not mistake this for all-stage completion.

### Other verified behavior

- `MetalCameraTests`: six checks including two projection cases passed under Xcode.
- `MetalSceneLoaderTests`: finite fixture geometry, scene selection, corruption,
  authored morph rest weight, tangent orthogonality and vertex stride passed.
- `MetalRendererTests`: BoomBox offscreen image, transparent backdrop, sRGB tag,
  deterministic repeated still and damaged-file error passed.
- All original21 models rendered at64² without a GPU failure.
- `MetalEnvironmentBakeTests` generated all3 environments successfully.
- Standalone shader compilation worked after installing the Metal compiler.
- Original21 PNGs did not change. `git diff --numstat TestModels/References` showed only
  additions to manifest.json, and new PNGs are untracked additions.

No full `./scripts/dev.sh test`, bench, release/install, extension process, real window, or
UI suite has completed for the port. Do not report those as passing.

### Expanded suite: known failures before the final handoff rerun

`/tmp/metal-extended-gpu.log` tested the expanded manifest after references were recorded.
The original21 still passed. Additional results:

| New sample | Result |
| --- | --- |
| CompareSheen | FAIL: mean0.279, bad0.7782% |
| CompareIridescence | PASS: mean0.031, bad0.0015% |
| CompareAnisotropy | FAIL: mean0.181, bad0.2686% |
| CompareSpecular | PASS: mean0.049, max14 |
| CompareIor | FAIL: mean1.028, bad1.0693% |
| CompareVolume | FAIL: mean0.521, bad0.5058% |
| CompareDispersion | FAIL: mean0.189, bad0.2647% |
| DiffuseTransmissionTest | PASS: mean0.107, max7 |
| BoxDraco | PASS: exact |
| MeshoptCubeTest | THROWS: unsupported required KHR_meshopt_compression |
| StainedGlassLampKTX2 | Not reached after the throw |
| ChronographWatchWebP | Not reached after the throw |

The all-sample smoke test also stops at MeshoptCubeTest. It does not verify the two following
compressed-texture entries yet.

## Fix these next

### 1. Meshopt sample and decoder mismatch

The plan reused GLTFKit2 0.5.15, whose bundled parser recognizes `EXT_meshopt_compression`.
The added MeshoptCubeTest from the pinned sample-asset revision uses the newer
`KHR_meshopt_compression`, including **COLOR** filter (along with OCTAHEDRAL,
QUATERNION, EXPONENTIAL). Do not blindly rename KHR to EXT; COLOR needs real decoder support.
An attempted broad rename was removed before handoff. Loader again rejects it honestly.

Options to evaluate: vendor/update native meshoptimizer and decode KHR bufferViews before
passing to GLTFKit2, or use a genuine EXT sample for the plan's EXT coverage while tracking
KHR support separately. The sample tree in `/tmp/khronos-sample-tree.json` lists
`Models/BrainStem/glTF-Meshopt-EXT` and `Models/DragonAttenuation/glTF-Meshopt-EXT`.
Do not quietly skip a failing sample or weaken the gate.

### 2. Transmission background correction needs retesting

After the expanded failures, source inspection found that
`environmentRenderer.drawEnvironmentMap()` returns immediately when
`renderEnvironmentMap == false`. The page always keeps that false, including transmission.
The native implementation had drawn an environment into the transmission prepass.
**That native environment draw was removed after the expanded run.** This should fix the
incorrect grey rather than black area of CompareIor, and may change volume/dispersion.
Its unused shader entry remains and can be removed in cleanup.

Also check:

- Transparent/transmission ordering currently uses world-origin distance, while Khronos sorts
  primitive **indexed vertex centroid transformed to view-space Z**. Port that exact sort.
- Main draw list doesn't explicitly separate opaque → transmission → alpha-blend groups.
- Prepass unlit materials still need Khronos `toneMapInverse` under TRANSMISSION_PASS.
- Confirm 1024² aspect/projection, framebuffer Y flip and mip LOD against upstream.
- Scatter prepass is absent; material volume-scatter data is not fully represented.

### 3. Sheen and anisotropy

Inspect actual/expected/diff PNGs and compare exact source functions. The hand port has the
features, but equations/inputs/interpolation still differ. Useful pinned originals were
extracted to `/tmp/khronos-*.glsl` and `.pretty` files. Durable source is:

```bash
git show f1fd1af:Vendor/web-renderer/gltf-viewer.module.js
```

Important locations in that readable bundle:

- shader strings at70064–70108 (`pbrShader`, `brdfShader`, `materialInfoShader`,
  `iblShader`, `specularGlossinesShader`, etc.)
- `updateTextureTransforms` around70430
- `generateTangents` around85654 and its calling condition around84555
- IBL filter and environment setup around88245–90999
- centroid generation around85038; depth sorting around12854

CompareSheen/CompareAnisotropy lack authored tangents. Verify the exact condition when the
page generates Mikk tangents versus its derivative tangent path. The loader generates them
for all triangle primitives with UV0. The page's conditional may differ.

### 4. Verify the latest controls work

The last edits added overlays, subtree bounds, file-camera matrices and host plumbing.
They were not covered by the earlier green21 run. Run and inspect the final handoff rerun,
then add meaningful native controls/fit/wireframe tests analogous to the WebKit ones.

Remaining concerns: centering off currently targets zero rather than porting the full authored
origin framing rule; zoom doesn't update near/far planes; debug absent-data checkerboard
is incomplete; overlays have not matched the page's exact line geometry/AA; live/background
presentation and file camera are not verified. `redraw()` now requires a hosted window to
avoid consuming CAMetalLayer drawables before mounting.

### 5. Measure and optimize; then cut over all surfaces

```bash
./scripts/dev.sh test
./scripts/dev.sh bench
```

`MetalBenchTests.swift` adds `mtl.thumb.cold`, `mtl.thumb.warm`, `mtl.gpu`,
`mtl.pipeline`, `mtl.process` rows under PerfBench. They have not been run. Footprint is the
whole hosted test process, not a native-only app. Cold-process and sandboxed-thumbnail
measurements still need separate evidence. Run timed benches alone.

The render path still allocates frame targets every frame, waits synchronously for GPU completion
and reconstructs uniforms each draw. Pipeline states/material resource argument buffers are
cached. Source compile is build-time only. The plan's feature function constants and more
complete load-time preparation remain unfinished; do not add archives before measurement.

Only switch/delete Filament after parity, controls and all three surfaces are verified. The
factory in `CanvasRendererHost.swift` is the single switch; no user-facing renderer preference.

## Pitfalls already fixed: do not regress

- GLTFKit2 primitive type enum inserts Invalid=0; subtract1 before mapping glTF modes.
  Missing this turned6036 BoomBox triangles into18106.
- GLTFKit2 sampler fields are **0 when unspecified**. Map0→LINEAR/LINEAR_MIPMAP_LINEAR
  before creating Metal samplers. This fixed alpha-test speckling and text aliasing.
- Khronos interpolates normalized vertex tangent **and bitangent** separately. Rebuilding
  bitangent with a fragment cross product failed BoomBox and negative-scale parity.
- This pinned Khronos UV matrix uses columns `(c,-s)` / `(s,c)`. It also transforms the
  vertex tangent/bitangent with the normal-map UV matrix. Matching this fixed TextureTransformTest.
- Pinned Khronos treats the specular-glossiness texture as **linear**, despite the expected
  spec colour semantics. Setting the native slot to sRGB caused a large mismatch.
- Keep straight8-bit PNG semantics: render/blend in half-float, tone toRGBA8, then unpremultiply
  readback bytes. Tag CGImage sRGB. Live CAMetalLayer presentation uses premultiplied output.
- Generate sRGB colour mips using an sRGB texture, not a linear mipchain viewed as sRGB.
- Publish pure C headers through RendererMetal.h; keep metal_stdlib outside that umbrella.
- New fixture JSON writes use `.withoutEscapingSlashes` to preserve data-URI loading.

## Reproduce environment bakes and new references

Bakes are exact filtered textures exported from the pinned WebGL page. The page has a test-only
`exportEnvironment` method; `setTexture(undefined,...)` is intentional because `null` returns
before initializing the GPU texture. It restores framebuffer bindings after readback.

```bash
TEST_RUNNER_GLTF_METAL_BAKE=1 ./scripts/dev.sh test \
  -only-testing:GLTFInspectorTests/MetalEnvironmentBakeTests
```

The generator now writes LZFSE-compressed binary Codable plists and deduplicates LUTs into
`shared.metalibl`. Runtime loads the same format. This generator-format revision was not itself
rerun after compression; existing assets were converted losslessly by a one-off Swift utility.
The native compressed loader was exercised by the expanded GPU run.

To record **only newly-added** manifest entries with no camera, without overwriting old PNGs:

```bash
TEST_RUNNER_GLTF_METAL_ADD_SAMPLES=1 ./scripts/dev.sh test \
  -only-testing:GLTFInspectorTests/MetalSampleReferenceTests
```

That ran successfully for12 new entries (`/tmp/metal-add-references2.log`). Original21 poses and
PNGs remained unchanged. Several WebP decoder diagnostics appeared, but a fully textured watch
reference was produced and visually inspected. Validate native/WebKit WebP decoding explicitly.
Do not run full reference regeneration to conceal native differences.

Environment variables need the **TEST_RUNNER_** prefix because xcodebuild doesn't forward
ordinary shell variables. The test sees the name without that prefix. Strict Metal parity is
opt-in during development; normal tests include native smoke tests, so a default green run
alone is not proof of parity.

## Toolchain and local evidence

The machine lacked the Metal compiler at the start. Default download requested unavailable
27B52; this command installed the version Xcode reported and compilation then worked:

```bash
xcodebuild -showComponent MetalToolchain -json
xcodebuild -downloadComponent MetalToolchain -buildVersion 27B47
xcrun metal --version
```

An older cached toolchain DMG was also mounted read-only at
`/Volumes/MetalToolchainCryptex` while diagnosing this; it is not used by builds. It can be
unmounted after checking no process uses it. No Xcode app files were modified.

Useful logs: `/tmp/metal-gpu7.log` (green21), `/tmp/metal-extended-gpu.log` (expanded failures),
`/tmp/metal-add-references2.log` (new goldens), `/tmp/metal-bake-test6.log` (successful bake),
`/tmp/metal-handoff-verification.log` (latest edits). Copy needed evidence somewhere durable
before `/tmp` is cleaned. Shader attribution is in `RendererMetal/Shaders/UPSTREAM.md`,
LICENSE.md and THIRD_PARTY_NOTICES.txt.

## Final handoff verification

The final targeted rerun **built successfully**, including the latest overlay/file-camera
edits. `MetalCameraTests` and `MetalSceneLoaderTests` passed. The strict pixel suite failed
as expected on remaining expanded coverage; this is **not** a green overall run.

- All original21 references still pass, including LightsPunctualLamp (mean0.023, max15).
- CompareVolume now **passes**: mean0.041, bad247/262144 (0.0942%), after removing the
  incorrect transmission environment background. It is close to the bad-pixel budget.
- CompareIor improved but still fails: mean0.389, bad0.5836%.
- CompareSheen, CompareAnisotropy and CompareDispersion still fail at the values above.
- CompareIridescence, CompareSpecular, DiffuseTransmissionTest and BoxDraco pass.
- MeshoptCubeTest still throws unsupported KHR_meshopt_compression; the two texture-
  compression entries after it remain unreached by the strict suite.

The run reported12 tests in3 suites with5 issues (four image mismatches plus the meshopt
throw), approximately17 seconds. No code edits followed this verification. Documentation
and backlog-link updates only followed it.

Durable filtered evidence: [native Metal verification](2026-11-04-native-metal-verification.txt).
The source log remains `/tmp/metal-handoff-verification.log`.
