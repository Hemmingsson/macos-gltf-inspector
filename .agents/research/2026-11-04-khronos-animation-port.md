# Khronos animation, skinning and morphing: port plan for the Metal renderer

Date: 2026-11-04. Scene-interaction plan Phase 6.1
(`.agents/plans/2026-11-04-scene-interaction.md:191`).

## Answer first

- **Port the Khronos GPU path.** The CPU evaluates the pose each frame: node TRS, world matrices,
  joint matrices and weights, a few KB in all. The vertex shader does the skinning and morphing
  from buffers that stay fixed after load. Re-baking on the CPU every frame would cost O(vertices)
  per frame and would need new buffers each frame, and `materialResources` is keyed by the vertex
  buffer's identity (`Renderer/MetalRenderer.swift:331`). It would also keep the skinning math,
  which differs from Khronos today (see "Gaps" below).
- **The reference stills are the rest pose.** No animation was active when they were rendered, so
  the GPU path cannot move any existing PNG, provided the rest path stays bit-identical (see
  "Keeping the references").
- **No skinned sample is in `manifest.json`.** Only `AnimatedMorphCube` (default weights `[0,0]`)
  and `InterpolationTest` (node TRS only) are animated. Skinning has no Khronos reference yet.
- **Leave `KHR_animation_pointer` for later (6.5).** Design the channel target as an enum so the
  pointer case fits in later.

## Evidence: how the references were taken

- The PNGs came from the in-app WebKit page (`80b3802`, "Regenerate web pixel-diff goldens").
  The page is recoverable at `f1fd1af:Vendor/web-renderer/viewer.html`, and the pinned bundle at
  `f1fd1af:Vendor/web-renderer/gltf-viewer.module.js` (the same pin as `Renderer/Shaders/UPSTREAM.md`,
  commit `863b981`). Line numbers below refer to that bundle.
- `viewer.html` never touches `animationIndices` or `animationTimer`. In `GltfState`,
  `animationIndices = []` and `AnimationTimer.paused = true` (bundle 69375, 13417).
- `GltfView._animate` (bundle ~91190): an animation outside `animationIndices` gets
  `advance(gltf, undefined)`. `interpolate` then returns `undefined`, and
  `animatedProperty.rest()` clears the animated value. **So the stills are the rest pose: the
  authored TRS and node/mesh default weights. They are not t=0.** For `AnimatedMorphCube` that is
  weights 0, the base cube.
- Today `scripts/regenerate-pixel-references.sh` renders with *Metal* (`PixelDiffRegenerationTests`).
  It cannot make new Khronos references. A new animated reference needs the Khronos renderer
  itself (see step 6.3d).

## 1. How Khronos evaluates animation (pinned bundle)

| Topic | Behaviour | Source |
| --- | --- | --- |
| Time | `elapsedSec()` = (now − start)/1000 while playing, the frozen `pausedTime` while paused. **Bug:** `fixedTime \|\| now…`, so `setFixedTime(0)` falls back to wall time | `AnimationTimer` 13417 |
| Wrap | Per animation, `maxTime` = max of channel `input.max`. `t %= maxTime`. If negative, or it wraps to exactly 0 (and the input was not 0), add `maxTime`. Then clamp to the channel's `[input[0], input[last]]`. Every clip loops, and a channel shorter than its clip holds its last key | `gltfInterpolator.interpolate` 86268+ |
| Key search | Cached `prevKey`, reset to 0 when t goes backwards. `nextKey` = first i with `t <= input[i]`, clamped to ≥1. `tn = (t − t_prev)/(t_next − t_prev)` | same |
| Single key | `output.length == stride`: return the key unchanged | same |
| STEP | Value at `prevKey` (quaternions too, not normalized) | same |
| LINEAR | Component-wise lerp. Rotation: **slerp** = normalize both keys, gl-matrix `slerp` (shortest path: negate when `dot < 0`; plain lerp when `1 − cos ≤ 1e-6`), then normalize | `slerpQuat`, `slerp` 2463 |
| CUBICSPLINE | Hermite with tangents scaled by `keyDelta`; layout [in-tangent, value, out-tangent] per key. Rotation is normalized afterwards | `cubicSpline` |
| Weights | Target `/nodes/n/weights` if the node has weights, otherwise `/meshes/m/weights`. Stride = rest array length | `gltfAnimation.advance` 87355+ |
| Node matrix | If `node.matrix` is set, the node is never animated (`getLocalTransform`) | 85912 |
| Precision | gl-matrix in Float32 (Float64 only for `KHR_accessor_float64` inputs) | `setMatrixArrayType` |
| Which clips | Renderer: only `state.animationIndices`. Sample Viewer app on load (`src/main.js:206-212`, `KhronosGroup/glTF-Sample-Viewer`): select greedily every clip that is disjoint from the ones already selected (`nonDisjointAnimations`, bundle 87996), then `animationTimer.start()`, which plays them | — |
| UI | Multi-select clip list; conflicting clips are disabled (`publishDisabledAnimations`); play/pause; reset (timer back to 0) | `main.js:409-434` |

"Disjoint" means the two clips share no target property (`computeDisjointAnimations`, 87943).

## 2. How Khronos skins and morphs on the GPU

**Skin** (`gltfSkin.computeJoints`, 87690). It runs every frame for every node that has both a
mesh and a skin (bundle ~72056).
- `joint = jointNode.worldTransform * IBM[i]`. The skinned mesh node's world matrix is **not**
  inverted out.
- `normal_i = transpose(invert(joint))`.
- The data goes into an RGBA32F texture of size `ceil(sqrt(joints*8))`², 8 texels per joint
  (4 columns of the joint matrix, then 4 of the normal matrix). The shader fetches matrix
  `jointIndex*2` and `jointIndex*2 + 1`.

**Vertex shader** (`primitiveShader`, `animationShader`, bundle 70080/70088). Defines:
`USE_SKINNING` (needs `skinning`, `node.skin`, JOINTS and WEIGHTS), `HAS_JOINTS_0/1_VEC4`,
`HAS_WEIGHTS_0/1_VEC4`.
- `skin = Σ w·joint` over JOINTS_0/WEIGHTS_0 and JOINTS_1/WEIGHTS_1. Weights are **not**
  renormalized. If `skin == 0` the matrix is the identity.
- `skinN = Σ w·normal_i`: the blended normal matrices, not the inverse of the blended matrix.
- Position: `pos = skin * (a_position + morph)`, with **no model matrix**.
- Normal: `normalize(u_NormalMatrix * (skinN * (n + morph)))`. **Quirk:** the mesh node's normal
  matrix is still applied.
- Tangent: `u_ModelMatrix * (mat3(skin) * (t + morph))`. Same quirk.
- The draw sets `u_ModelMatrix` and `u_NormalMatrix` from the mesh node's current world matrix.
  `frontFace` is CW when `det(world) < 0`, chosen per draw every frame (73012).

**Morph** (`gltfPrimitive`, 84797+, `updateAnimationUniforms`).
- Attributes are the union over all targets: POSITION, NORMAL, TANGENT, TEXCOORD_0/1, COLOR_0.
- Storage is one `sampler2DArray` RGBA32F, `width = ceil(sqrt(vertexCount))`. Layer =
  `MORPH_TARGET_<ATTR>_OFFSET + targetIndex`. vec2 and vec3 values are padded to vec4.
- The array is indexed by `gl_VertexID`, the original glTF vertex.
- Only float or normalized accessors are used.
- Targets are capped at `MAX_ARRAY_TEXTURE_LAYERS / attributeCount`.
- `USE_MORPHING`, `WEIGHT_COUNT = getWeights().length`, `uniform float u_morphWeights[WEIGHT_COUNT]`.
- Deltas are added before skinning. Color is `clamp(c + Δ, 0, 1)`. UVs get their deltas.

## 3. Recommendation for this renderer

### Gaps in today's CPU bake (`Renderer/Scene/MetalSceneLoader.swift:160-206`)

Once the GPU path follows Khronos's math, these are all fixed:
- Weights are renormalized by their sum (Khronos does not).
- Normals use `inverse(blended)ᵀ` (Khronos blends the normal matrices).
- The mesh node's normal matrix is dropped (`inverse(model)` is folded in, then `model` is applied again).
- JOINTS_1/WEIGHTS_1 are ignored.
- Morph only applies POSITION, NORMAL and TANGENT; TEXCOORD and COLOR deltas are skipped.
- Morphing happens *before* MikkTSpace and face-normal generation. Khronos generates from the base shape.

No reference covers any of these today, so fixing them moves no PNG.

### Data kept at load

- **`MetalVertex` (80 B) is unchanged.** It holds bind-pose, unmorphed attributes, laid out as now.
- **A new optional per-draw `skinBuffer`.** One `{ushort4 j0, ushort4 j1, float4 w0, float4 w1}`
  per *emitted* vertex (48 B). Joint indices are into `skin.joints`.
- **A new optional per-draw `morphBuffer`.** `float4` deltas laid out
  `[attributeSlot][target][emittedVertex]`, plus a small header (target count, attribute mask,
  slot offsets) in the draw uniforms.
- **The deindex problem.** The loader deindexes for face normals and MikkTSpace
  (`deindexed`, `MetalSceneLoader.swift:238-252`). Have `deindexed` also return the source-vertex
  map, then gather the skin and morph streams through it. The shader indexes by `vertex_id`,
  already the emitted vertex (`pbr.metal:21-26`, a `device` buffer, no stage_in).
- **New `MetalDraw` fields:** `skinIndex: Int?`, `weightCount`, and `restWorld` (today's
  `worldTransform`, renamed). `worldTransform`, `negativeScale` and the normal matrix become
  per-frame values passed in by the frame (an array indexed by draw). For instanced draws, also
  keep the instance matrix.
- **A new `MetalScene.pose` model.** It holds:
  - the node parent array (Phase 1.1 adds it);
  - per node: rest TRS and `hasMatrix`, plus the rest local matrix taken from GLTFKit2
    `node.matrix` exactly as today;
  - skins: joint node indices and IBMs;
  - each draw's node index and instance matrix;
  - rest weights per draw.

### Evaluated per frame (only when a clip is active or the time changed)

1. **6.2 sampler** (pure Swift, GLTFKit2 `GLTFAnimationSampler.input/output/interpolationMode`).
   It produces `[node: TRS override]` and `[node or mesh: weights]`, following the table in §1.
2. **Local matrix.** For an overridden node: Float32 `fromRotationTranslationScale`. For any other
   node: the rest local matrix, unchanged. World = parent·local, walked in the same order as
   `collect`.
3. **Joints.** Per skin, `joint = world[jointNode] * IBM` and `normal = transpose(inverse(joint))`,
   into one `MTLBuffer` of `float4x4` pairs. Use a ring of 3 for frames in flight, or
   `setVertexBytes` when it is 4 KB or less.
4. **Weights.** Per draw, `setVertexBytes` of `float[weightCount]`.
5. **Draw uniforms.** Per draw, `model = world[node] * instance` and
   `normalMatrix = model.inverse.transpose` (as at `MetalRenderer.swift:325`), and front facing
   from `det(model)`.

### Shader

- In `khronos_vertex`, add Metal **function constants** `hasSkin`, `hasJoints1` and `morphMask`.
  With all of them false, the generated code is today's shader, so rigid draws stay
  bit-identical.
- The skinned branch mirrors Khronos exactly, quirks included:
  - `p = skin*pos` (the model matrix is skipped)
  - `n = draw.normalMatrix * (skinN*n)`
  - `t = draw.model * (skin*t)`
  - identity when the weight sum is 0
- Pipeline cache key: add the constants (`MetalRenderer.swift:342`).

### Keeping the references

Every existing reference stays identical at rest if three things hold:
- **Rigid draws** use the unchanged shader specialization (function constants false). When no
  clip is active, the per-frame world for every node is the cached load-time `parent * node.matrix`,
  the same Float math. Recompute through TRS *only* for animated nodes while a clip is active.
- **`AnimatedMorphCube`** runs the morph branch with weights 0, so `pos + 0·Δ = pos` exactly and
  normals are unchanged. Also gate on `any weight != 0` and use the rigid specialization when all
  are 0. That makes it exact by construction, matching the current loader's `!= 0` skip.
- **Skinned files** have no reference. The tests on fixture `rigged/two-joint-skin.gltf` are
  shape checks (`MetalSceneLoaderTests`), not pixel checks.

To compare float precision between the CPU-at-load path and the GPU path, add a unit test that
renders the `rigged` and `morph` fixtures both ways. Expect the GPU result to differ slightly, by
FMA ordering; it should be within the tolerance and is not required to be bit-equal.

## 4. Depth-sort centroids, bounds and `opaqueGroup` under animation

| Item | Khronos | Port |
| --- | --- | --- |
| Centroid | Computed once from authored POSITION and indices (bundle 85027). Never morphed or skinned | Unchanged (`MetalSceneLoader.swift:204-208`) |
| Sort depth | Per frame: `view * node.getRenderedWorldTransform()` applied to the centroid (12854). Skinned draws use the mesh node's world matrix | `viewDepth` (`MetalRenderer.swift:460`) takes the per-frame model instead of `draw.worldTransform` |
| `opaqueGroup` | Built in `prepareScene` only when the node list changes (~71904). Winding comes from the world matrix at that moment; skin and morph draws get unique keys | Unchanged: rest winding, built once |
| Front face | Per draw, per frame, from `det(world)` | `negativeScale` per frame |
| Extents / fit | `getSceneExtents`: accessor min/max × current world, skin ignored. The Sample Viewer fits on load, at rest | Keep `boundsMin/Max` at rest (plan 6.3). **Watch:** bounds come from the CPU-skinned vertices (`GLTFMetalBounds`, :258). Once the loader stops skinning, compute rest bounds once on the CPU through the same joint math, or skinned bounds move |

## 5. KHR_animation_pointer

The pinned renderer supports it fully.
- It lists `KHR_animation_pointer` in `allowedExtensions` (87767).
- It resolves any JSON pointer to an `AnimatableProperty`. The `static animatedProperties` lists
  cover:
  - material factors and every `KHR_materials_*` factor;
  - `KHR_texture_transform` offset, scale and rotation;
  - lights (color, intensity, range, cone angles);
  - cameras (yfov, aspect, znear, zfar, xmag, ymag);
  - node TRS and weights;
  - `KHR_node_visibility` visible;
  - interactivity hover and select.
- Booleans are thresholded with `!= 0`.

**Later.** No pinned sample uses it, and our materials, lights and visibility are baked into
`MetalScene` at load, so each pointer family needs its own per-frame plumbing. In 6.2, make the
channel target an enum (`.translation`, `.rotation`, `.scale`, `.weights`, `.pointer(String)`) and
ignore `.pointer` for now. Bring it in as 6.5 starting with node TRS and weights, the cheapest
family because it reuses 6.3, then material factors.

## 6. Steps (ticket-sized)

1. **6.2a Sampler core.** `AnimationSampler.evaluate(t)` for STEP, LINEAR and CUBICSPLINE, with
   quaternion slerp and normalization, Khronos wrap and clamp, and the single-key case.
   *Check:* Swift Testing on hand-made keyframes for every mode. Include:
   - a quaternion shortest-path flip;
   - a t past the end, a negative t, and t exactly equal to `maxTime` (it lands on the last key);
   - a channel shorter than its clip.
2. **6.2b Clip and pose.** `AnimationClip`, built from GLTFKit2 (`maxTime` = max of `input.max`),
   and `Pose(clips:t)` giving TRS overrides and weights. Weights target node weights when present,
   otherwise mesh weights. Matrix nodes are skipped. Also the default selection: greedily pick the
   disjoint clips.
   *Check:* `InterpolationTest` and `BoxAnimated` poses at t=0.5 match values computed by hand.
3. **6.3a Per-frame transforms.** Add the `MetalScene` pose model and per-frame `model`,
   `normalMatrix` and front face. With no clip active, use the cached rest worlds. Make `viewDepth`
   use the per-frame model.
   *Check:* `./scripts/dev.sh test`, with every pixel reference unchanged. Then a unit test:
   `BoxAnimated` posed at t moves its draw's model matrix and its sort depth.
4. **6.3b GPU morph.**
   - Gather morph deltas through the deindex map into `morphBuffer`.
   - Add the function constant branch, with weights passed via `setVertexBytes`.
   - Stop baking morph in the loader; generate MikkTSpace and face normals from the base shape.
   - Add TEXCOORD and COLOR deltas.

   *Check:* references unchanged, including `AnimatedMorphCube`; the `morph` fixture with weight 1
   matches the old CPU bake within 1e-5.
5. **6.3c GPU skin.**
   - Add `skinBuffer` (JOINTS_0/1, WEIGHTS_0/1) and the per-skin joint buffer.
   - The shader follows Khronos's quirks.
   - Rest bounds come from a one-off CPU skin pass.

   *Check:*
   - references unchanged;
   - `rigged` fixture bounds equal to the old ones;
   - posing a joint moves only the weighted vertices (readback test).
6. **6.3d Khronos references for animation.**
   - Revive the `f1fd1af` page in a throwaway worktree and harness. Add a command that sets
     `state.animationIndices = [i]` and `animationTimer.setFixedTime(t)`, with t > 0 because of
     the `fixedTime || now` bug.
   - Render `AnimatedMorphCube` at t = 0.5 and 1.0, and one skinned sample at a fixed t (add
     `SimpleSkin` or `RiggedSimple` to the manifest). Add an optional
     `animation: {index, time}` to manifest entries.

   *Check:* the new PNGs pass, and you have looked at them against the Sample Viewer.
7. **6.4a Playback model.** On `ModelCanvasController`: clip selection, play/pause, t, loop and
   speed. `ModelView`'s display link runs while playing (`Renderer/ModelView.swift:246`). Thumbnails
   and Quick Look stills stay at rest.
   *Check:* unit test that t advances with the clock and that a scrub re-poses.
8. **6.4b Timeline HUD.** Glass HUD, Space toggles play, clip picker, the Animations row sets the
   clip, live morph weights in the inspector.
   *Check:* UI test (play advances t, scrub changes the pose) and a look on screen.

## Risks

- Moving morph and skin out of the loader also changes **MikkTSpace input**: tangents are
  generated from the base shape instead of the default-weighted one. That matches Khronos, but it
  could move a non-reference file that has non-zero default weights and no tangents. Confirm no
  manifest sample is like that (`AnimatedMorphCube` has weights 0).
- **Skinned-mesh bounds and camera fit** change if the rest bounds are not kept (§4).
- The **4 KB `setVertexBytes` limit**: more than 32 joints needs a real buffer and a ring for
  frames in flight.
- The **draw-filter / per-frame path** is shared with Phase 1.2. Land 6.3a after 1.2 so the two
  don't conflict.
- **New Khronos references** depend on reviving the deleted WebKit page. That is test tooling only
  and must not ship.

Unresolved: the Khronos viewer *plays* all disjoint clips on load. Should our window autoplay too,
or open paused at rest (stills are always rest)? That is a product decision for 6.4.
