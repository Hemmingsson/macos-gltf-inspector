# Critical implementation review — 2026-11-04

Working handoff for improving the renderer port and scene-interaction implementation. Findings are
being added and verified as the review proceeds. This is a review, not a patch or merge approval.

## Review scope and evidence

- Baseline at review time: main around `dbc169fc` plus in-progress scene-interaction work.
  Findings below still apply unless noted fixed. Scratch logs/patches from the probe worktree
  were removed after the epic landed on `main` (`1cbee80`); this file is the durable record.
- Completed work under review: visibility/filtering, GPU picking, click routing, reveal/frame,
  navigation gizmo, camera/light gizmos and hit testing, skeletons, shared scenes, animation
  sampler through GPU skin/morph, playback, timeline, and silhouette outline.

## Summary for the handoff (priority order)

Backlog: epic `6ddtcd5k` ("Review fixes") breaks these findings into 11 L1s and 41 leaves, ordered by impact (`dex list 6ddtcd5k`).


| ID | P | Defect | Probe |
|----|---|--------|-------|
| R15 | P1 | Frame Selection re-measures the scene: rest of model far-clipped, floor/gizmos resize | red |
| M01 | P1 | Morph deltas applied after the CPU skin bake (spec: morph then skin) | traced + math |
| M02 | P1 | Click/hover picking uses the rest pose during animation (also V04) | traced |
| V01 | P1 | Scroll/pinch zoom dead in axis (ortho) views; next orbit jumps | replay |
| V02 | P1 | Orbit-around-selection re-aims on every pick, breaking click-cycle | traced |
| R4 | P1 | Framing a camera/light/joint/empty gives a non-finite projection | red |
| R9 | P2 | Occluded camera/light gizmos win clicks over the visible mesh | red |
| R10 | P2 | BLEND picks by draw order; transparent texels pickable | red |
| R6 | P2 | Scene 0 unselectable when the file's default scene is not 0 | red |
| R7 | P2 | Gizmos include other scenes' and authored-hidden cameras/lights | red |
| A3 | P2 | Outliner rows from inactive scenes can be soloed/selected/framed | traced + replay |
| R12 | P2 | Mesh-less scenes cannot load; failed apply leaves options out of sync | red |
| R1 | P2 | STEP sampling wrong at exact keys and after channel end | red |
| R2 | P2 | Gizmo segments crossing the viewport unpickable | red |
| R3 | P2 | Gizmos beyond the far plane still pickable | red |
| R5 | P2 | Frame Selection includes origin when Center Model is off | red |
| R8 | P2 | Nested groups show a parent link instead of their subtree box | red |
| A1 | P2 | Stale camera preset after canvas orbit flips the gizmo to the opposite view | traced |
| A2 | P2 | Vertical gizmo drag orbits opposite to canvas drag | replay |
| R11 | P2 | Per-frame full-size GPU allocations + main-thread GPU wait | traced |
| A4 | P2 | `CanvasRegion` body and subtree bounds recomputed every camera frame | traced |
| P-A1, P-A2 | P2 | (in progress) morph weights dropped without mesh defaults; malformed sampler traps | traced |
| M03–M06, M08 | P2 | Overlays/bounds/lights on rest pose; frozen generated normals; dense morph memory; highlight ignores variants; clips parsed on main | traced |
| H01–H06 | P2 | Playback/timeline: no replay after end, scrub fights playback, short clips loop with loop off, "All" mislabelled, HUD overlaps readout, vacuous tests | replay / traced |
| V03, V05, V06 | P2 | Ortho retarget tilts view; turntable reads live camera; failed export destroys file | replay / traced |
| R13, R14, A5–A8, P-A3, M07, M09, M10, V07–V11, H07–H09 | P3 | lookups, cycle guards, preview, range primary, pointer keys, highlight extent, skinned node transform, turntable pose, X-ray order, hover cost/insets, dimensions, totals | traced |

Common roots worth fixing once rather than per finding:
0. **The animation pose reaches only `drawTransforms`** (M02, M03, M10, V04): picking, overlays,
   bounds, lights, file cameras and export all read rest matrices. Publish posed node worlds once per frame.
1. **No single "active scene membership + effective visibility" resolution** (R6, R7, A3, part of R12).
   Build it once in `MetalScene` and reuse for draws, overlays, picking, outliner and inspector.
2. **`MetalUserCamera.fit` serves both whole-scene fit and selection framing** (R4, R5, R15).
   Split target/distance framing from scene measurement and clip-plane fitting.
3. **Picking does not share the render's visibility rules** (R2, R3, R9, R10). Give the pick pass
   depth for every draw and test gizmo hits against it.
4. **Camera state changes in `ModelView` are invisible to `ViewState`** (A1, A7, V03) and **every redraw
   re-renders from scratch and invalidates SwiftUI** (R11, A4).

## Confirmed findings

### R1 · P2 · STEP sampling returns the previous value at exact keys and after the channel ends

**Location:** `Renderer/Scene/AnimationSampler.swift:48–57,111–120`.
**Task:** `ifz67ezm` (completed).

The sampler finds the first key at or after `t`, then STEP always returns the key before it.
For keys `[0,1,2]` and values `[0,10,20]`, sampling at `1` returns `0`; sampling at `7` in a
10-second clip clamps to the final key and returns `10`, so the channel never holds its final
value. This violates exact-key and endpoint behavior.

**Verified:** compiled the real sampler source in a standalone Swift harness (probe logs removed
after shipping). The [glTF interpolation specification](https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html#interpolation)
requires exact key timestamps to use their associated values.

**Fix direction:** handle exact keys/endpoints before interpolation, or choose the last key at or
before `t` for STEP. Preserve the intended clip wrapping policy.

**Required regression:** STEP at every exact key, immediately before/after the middle key, and
past a short channel's endpoint within a longer clip. Existing endpoint tests only cover LINEAR.

### R2 · P2 · Visible gizmo segments crossing the viewport can never be picked

**Location:** `Renderer/GizmoHit.swift:82–91` (`segmentIsOffscreen`).
**Task:** `oebu83te` (completed).

The broad-phase check rejects a segment whenever both endpoints are outside the viewport.
Endpoints on opposite sides can still form a line through the entire visible canvas. With an
identity projection and a 100×100 viewport, `(-2,0,0) → (2,0,0)` is visible through the center,
but a pick at `(50,50)` returns nil instead of its node index.

**Verified:** standalone harness using the actual production function; see pure-reproductions.log.

**Fix direction:** reject only when both endpoints lie outside the same clip boundary, or clip the
segment to the view volume before the 2D distance test.

**Required regression:** segments crossing each pair of opposite boundaries, same-side misses,
and a segment crossing the near plane.

### R3 · P2 · Gizmos outside the depth clip range remain selectable

**Location:** `Renderer/GizmoHit.swift:52–65` (`gizmoProject`).
**Task:** `oebu83te` (completed).

Projection only checks `w > 0`; it ignores clip-space Z. An invisible segment beyond the far plane
still projects onto the canvas and wins before the mesh pick. Under an identity projection,
`(-0.5,0,2) → (0.5,0,2)` incorrectly returns its node for a center pick.

**Verified:** standalone harness using production code; see pure-reproductions.log.

**Fix direction:** clip in homogeneous coordinates using the renderer's OpenGL-style depth range,
then project the surviving segment. Do not discard an entire segment merely because one endpoint
crosses the near plane.

**Required regression:** fully before-near, fully beyond-far, perspective behind-eye, orthographic
behind-eye, and partially visible segments.

## Verification status

The captured full build is currently blocked in active clip/pose work:
`Renderer/Scene/AnimationClip.swift:211` reads `GLTFAccessor.type`, which the pinned GLTFKit2 API
does not expose. This is an in-progress integration observation, not proof that the completed
sampler or prior green builds failed. Full log: `snapshot-baseline.log` in the evidence directory.
Pure sampler and gizmo reproductions compile and run independently of that unfinished code.

## Next checks in progress

- Scene index zero versus a file whose default scene is nonzero.
- Frame Selection on camera/light nodes and zero-sized bounds.
- Scene membership/authored visibility in overlays and gizmo picking.
- File-camera picking, shared-scene lifetime, and preview update behavior.
- Native renderer resource limits and coverage quality.

### R4 · P1 · Framing a camera, light, joint, or empty leaf creates an invalid projection

**Location:** `Renderer/ModelView.swift:134–143`; `Renderer/Scene/MetalScene.swift` (`bounds(ofNode:)`);
`Renderer/MetalUserCamera.swift` (`fitCameraPlanesToExtents`). **Task:** `yo39dosw` (completed).

Non-mesh leaf bounds are a single point. Frame Selection passes that zero-extent box to the normal
camera-fit path. The resulting near and far planes are both zero, and the perspective projection
contains non-finite values. The canvas can disappear after framing an otherwise selectable light
or camera.

**Verified:** the actual production camera fit with bounds `(0,2,0)…(0,2,0)` produces
`znear = 0`, `zfar = 0`, and a non-finite projection; see pure-reproductions.log. The app command
accepts all scene-node kinds, not only meshes.

**Fix direction:** frame a bounded gizmo volume for non-mesh nodes or impose a sensible minimum
extent/clip range. Preserve finite, ordered near/far planes for every valid frame operation.

**Required regression:** full `ModelView.frame(nodeIndex:)` on a camera, light, empty leaf and
joint; assert a finite projection and that the next render succeeds. Add a degenerate mesh case.

### R5 · P2 · Frame Selection includes the world origin when centering is off

**Location:** `Renderer/ModelView.swift:140`. **Task:** `yo39dosw` (completed).

Selection framing passes the window's `isCentered` flag into `camera.fit`. With Center Model off,
that method expands the selection bounds to include the origin. A selected box spanning
`(10,0,0)…(11,1,1)` targets `(5.5,0.5,0.5)` instead of its center `(10.5,0.5,0.5)`. Small distant
parts therefore do not fill the canvas when explicitly framed.

**Verified:** production camera math in pure-reproductions.log; the call site forwards the same
flag. The existing Frame Selection test only covers default centering.

**Fix direction:** keep origin-inclusive behavior for whole-scene Fit; explicitly frame selection
bounds independently of that global framing preference.

**Required regression:** translated child, Center Model off, arbitrary orbit: target equals the
selection center, angles are preserved, and selected corners fit the viewport.

### R6 · P2 · Scene zero cannot be selected when the file's default scene is another scene

**Location:** `Renderer/ModelView.swift:76–77,103–105`;
`Renderer/Scene/MetalScene.swift:158–162`. **Area:** renderer/window scene integration.

The sidebar uses actual glTF scene indices, but the renderer-facing value uses `0` as a sentinel
for the file default. A file with `scene: 1` and two distinct scenes opens scene 1 correctly;
selecting the scene-0 row sends `0`, which becomes nil and loads scene 1 again. Its bounds also
resolve back to the default scene.

**Evidence:** direct end-to-end source trace from `Sidebar.activate` through `ViewState.sceneIndex`,
`ModelView.apply`, `MetalSceneLoader.build`, and `gltfSceneIndex(for:)`. **Reproduced** on main's
current tree: `sceneZeroCanBeSelectedWhenDefaultSceneIsOne` still draws node 3 after selecting scene 0.

**Fix direction:** use a real optional index for “file default”, or resolve the default to an
actual index before it reaches `ViewOptions`. Do not overload a valid array index.

**Required regression:** fixture with `scene: 1`, distinct roots/bounds in scenes 0 and 1; select
each scene and assert loaded draws, fit bounds and rendered output match that exact scene.

### R7 · P2 · Global gizmos include nodes outside the active scene and authored-hidden nodes

**Location:** `Renderer/MetalOverlays.swift:108–118`, `overlayGizmoSegments`; compare
`Renderer/Scene/MetalSceneLoader.swift:103–131`. **Tasks:** `y3hdxwwh`, `umczfxl2`, `oebu83te`.

Both overlay generation and gizmo hit-segment generation enumerate every `asset.nodes` entry.
They check the window's hidden set, but neither active-scene membership nor authored
`KHR_node_visibility`. The loader draws only the selected scene's visible subtree. Enabling
Show Cameras & Lights can therefore show and select a camera/light that does not belong to the
scene being rendered, or that the file explicitly hides.

**Evidence:** source trace. **Reproduced** on main's current tree: `gizmosExcludeCamerasOutsideTheLoadedScene`
and `gizmosExcludeAuthoredHiddenCameras` both return segments for the excluded cameras.

**Fix direction:** retain active-scene membership and effective authored visibility in `MetalScene`
and reuse one resolution for draw filtering, overlay geometry and picking. Define any intentional
selection-only exception separately from the global Show Cameras & Lights behavior.

**Required regression:** two disjoint scenes with different cameras/lights, an unreferenced camera,
and an authored-hidden parent containing a light. Compare visible segments and pick targets with
loaded scene membership.

### R8 · P2 · Nested groups are rendered as parent links instead of subtree bounding boxes

**Location:** `Renderer/MetalOverlays.swift`, `collectSelectionGizmo`'s non-mesh-parent branch.
**Tasks:** selection foundation / `y3hdxwwh` integration.

For any non-mesh node with a parent, selection returns early after drawing a single line to its
parent. Ordinary nested groups therefore lose their subtree AABB. The joint-specific path already
exists separately, so this branch incorrectly applies a bone-like visualization to arbitrary groups.

**Evidence:** source trace. **Reproduced** on main's current tree: `nestedGroupSelectionShowsItsDescendantBox`
gets one line instead of the 12-edge box, and no vertex near the mesh at x = 10.

**Fix direction:** ordinary groups should fall through to `bounds(ofNode:)` and the box renderer;
only actual joints should use skeleton logic.

**Required regression:** root → translated group → mesh: selecting the group produces a box around
its descendant mesh, not just a line between node origins. Preserve the true-joint tests.

## Continuation pass — main working tree (2026-11-04, afternoon)

Main had moved since the early snapshot: `MetalOverlays`, `MetalRenderer`, `ModelView`,
`ViewOptions`, `ViewState`, `DocumentWindowModel`, the inspector sections and several tests
differed from the probe worktree. This pass read **main's working tree** (read-only). Line
numbers may drift — function names are the stable anchor.
R1–R8 were re-checked against it and still hold unchanged: `AnimationSampler.swift:48–57,111–120`,
`GizmoHit.swift:57–86`, `ModelView.swift:77,102,135–143`, `MetalScene.swift:159–163,232–246`,
`MetalOverlays.swift:114–123,220–229,302–310`.

### R9 · P2 · Camera/light gizmos behind the model steal clicks from the visible mesh

**Location:** `Renderer/ModelView.swift:432–457`; compare `MetalRenderer.swift` `encodeOverlays`
(`occlude:` flag) and commit `1ea463b` ("Hide the floor, gizmo and selection lines behind the model").

Overlay lines are depth-tested against the stored scene depth, so a light or camera behind a mesh
is not drawn. Picking runs `gizmoHit` first and returns on any segment within 6 pt, with no depth
comparison. Clicking a visible wall in front of an occluded spot light selects the light.

**Evidence:** source trace plus probe `occludedLightDoesNotWinOverTheMeshInFront`: on the centre
pixel `renderer.pick` returns the opaque quad (node 0) and `gizmoHit` returns the light behind it
(node 1). `ModelView.performPickIfClick` tries the gizmo first, so the click selects the light.

**Fix direction:** compare the hit segment's depth at the closest point with the mesh pick depth
(read back the pick depth texture at the same pixel), or test the segment sample against the same
soft-depth rule the overlay shader uses. Keep "gizmo wins" only when it is actually visible. A file
camera disables occlusion when drawing (`occlude: fileCameraNodeIndex == nil`); picking must match.

**Required regression:** opaque quad between the orbit camera and a point light; click on the
light's projected position → mesh node, not light. Same scene with the quad hidden → light.

### R10 · P2 · BLEND materials pick by draw order, not nearest surface, and transparent texels are pickable

**Location:** `Renderer/MetalRenderer.swift` `encodePick` (`setDepthStencilState(blend ? depthRead : depthWrite)`);
`Renderer/Shaders/pbr.metal:343–354` (`khronos_pick_fragment`).

The pick pass copies the colour pass's depth state: BLEND draws test but do not write depth, so the
last BLEND draw covering the pixel wins. Draw order is the Khronos centroid sort, so a large
transparent mesh whose centroid is far away loses to a nearer-centroid mesh that is physically
behind it. The fragment also never discards BLEND texels, so alpha-0 holes in a BLEND texture
(foliage, decals) select the mesh behind the cursor's apparent background.

**Evidence:** source; `CriticalReviewRegressionTests.transparentPickingUsesNearestSurfaceRatherThanCentroidOrder`
**reproduced** on main's current tree: the pick returns the nearer-centroid node 1, which is
physically behind node 0.

**Fix direction:** the pick pass is a separate pass with its own pipeline: always write depth
there, and discard BLEND fragments below a small alpha threshold (e.g. 1/255 or a documented
selection threshold).

**Required regression:** the existing review test above; plus a BLEND quad with a fully
transparent texture in front of an opaque mesh → pick returns the opaque mesh.

### R11 · P2 · Every live frame allocates full-size render targets and blocks the main thread

**Location:** `Renderer/MetalRenderer.swift` `renderTexture` (hdr, flags, depth, output, 1×1 black),
`encodeOverlays` (4× MSAA target + frame copy + line buffer), `transmissionBackground`
(multisample colour + depth); all end in `command.waitUntilCompleted()` on the main actor.
`ModelView.redraw()` runs this synchronously for every drag, scroll and display-link tick.

At a 5K canvas (~5120×2880 px) one frame allocates roughly 120 MB rgba16F + 15 MB r8 + 60 MB depth
+ 60 MB rgba8 + 240 MB 4×MSAA + 60 MB copy, then waits for the GPU before returning to event
handling. Orbit drags and auto-rotate pay this per event. `pick` repeats it per click.

**Evidence:** source only; no profile captured in this pass. `GLTFInspectorTests/PerfBench.swift`
exists and should be used to measure before/after.

**Fix direction:** cache intermediate targets keyed by (size, sample count, format) on the renderer
and reuse them; keep one `output` per drawable size; let live frames present via
`addCompletedHandler`/`present(drawable)` instead of `waitUntilCompleted`. Keep the synchronous path
for stills/thumbnails.

**Required regression/measurement:** PerfBench run of 120 orbit redraws at 2560×1440 before and
after; assert allocations per frame drop to zero after the first frame (count via a test hook).

### R12 · P2 · A scene without mesh primitives cannot be shown, and the failed switch leaves options out of sync

**Location:** `Renderer/Scene/MetalSceneLoader.swift:132` (`guard !draws.isEmpty else throw`);
`Renderer/MetalRenderer.swift` `adopt` (`guard let draw = loaded.draws.first else throw .noScene`);
`Renderer/ModelView.swift:97–104` (`applyOptions(next)` runs before `renderer.load`).

The outliner lists every glTF scene, including ones that only hold cameras, lights or empty
groups (layout scenes, lighting rigs). Selecting such a scene throws "no renderable primitives".
`apply` has already stored the new `options.sceneIndex`, so the view now claims the new scene
while the renderer still draws the previous one; a later `apply` with the same index sees no
scene change and never retries. Frame/fit then use the new index against the old scene.

**Evidence:** source trace. **Reproduced** on main's current tree:
`cameraOnlySceneCanLoadWithoutMeshPrimitives` throws `.invalid("The glTF scene contains no renderable primitives")`.

**Fix direction:** allow an empty draw list (overlays, gizmos and file cameras still work; fit
falls back to node origins or the unit box). Independently, make `apply` transactional: load
first, commit `options` only on success, or roll back on throw.

**Required regression:** camera-only scene loads with `draws.isEmpty` and a finite camera;
an apply that throws leaves `view.options == previous` and a retry reloads.

### R13 · P3 · Loader and overlays resolve node indices with linear `firstIndex(of:)` per draw/joint

**Location:** `MetalSceneLoader.swift:120` (lights), `append` (`asset.nodes.firstIndex(of: node)` per
primitive *and* per instance, `asset.meshes.firstIndex`, `primitives.firstIndex`);
`MetalOverlays.swift:153–161` (`isSkinJoint`, `jointNodeIndices` — called every overlay frame).

Load is O(draws × nodes) `isEqual:` calls on `GLTFNode`; a 10k-node, 10k-draw scan file costs
~10⁸ comparisons before the first frame. The skeleton overlay runs O(skins × joints × nodes)
on every redraw while a joint is selected. `MetalScene.init` already builds an
`ObjectIdentifier → index` map for `nodeParents`; nothing else reuses it.

**Evidence:** source; not profiled.

**Fix direction:** build one identity→index map per asset (nodes, meshes, skins' joint indices)
in the builder and keep it on `MetalScene`; overlays read precomputed joint index arrays.

**Required regression/measurement:** PerfBench load of a generated 10k-node file before/after;
unit test that `MetalScene.jointIndices(skin:)` matches the linear lookup.

### R14 · P3 · Scene graph walks guard cycles in one place only

**Location:** `MetalScene.ancestors(ofNode:)` (bounded) versus `MetalScene.worldMatrix(_:)` and
`fileCamera` `world(_:)` (unbounded recursion), `bounds(ofNode:)`/`accessorExtents` (unbounded
child stack), loader `collect`/`visit`/`global`.

`ancestors` documents that it stops on a cyclic file; every other walk would recurse or loop
forever on the same file. If GLTFKit2 already rejects cycles, the guard in `ancestors` is dead
code; if it does not, the Quick Look extension can hang or overflow the stack.

**Evidence:** source; whether GLTFKit2 accepts a `children` cycle was not checked.

**Fix direction:** decide once — validate acyclicity at load (fail with a clear error) and drop the
ad-hoc guard, or share one bounded traversal.

**Required regression:** fixture with nodes 0↔1 as each other's child: load fails with a
`MetalSceneError`, or every walk terminates.

### R15 · P1 · Frame Selection replaces the scene measurement: the rest of the model is far-clipped and the floor jumps

**Location:** `Renderer/ModelView.swift:135–143` → `MetalUserCamera.fit` (`MetalUserCamera.swift:101–123`),
which assigns `sceneMin/sceneMax` and runs `fitCameraPlanesToExtents` (`:180–185`) on the
selection box; `ModelView.extents` (`:242–244`) feeds that same box to the floor, origin gizmo and
scene-gizmo sizing.

`fit` is the whole-scene fit reused for a subtree. After framing a small part:

- `zfar = distance + 6 × diag(part)`. A 0.1 m bolt on a 5 m machine gets a far plane ~0.6 m
  behind its centre, so most of the machine behind it disappears.
- The polar floor is re-centred at `low.y` of the part and resized to it; light/camera gizmos
  and the origin axes shrink to `0.15 × span(part)`.
- Pan speed and the 100 % zoom reference become part-relative.

Orbit or zoom afterwards keeps those planes until the next whole-scene fit.

**Evidence:** **reproduced** on main's current tree (`frameSelectionKeepsTheRestOfTheSceneInsideTheClipRange`):
framing a 0.1-unit quad with a 10-unit quad 20 units behind it leaves `zfar = 0.97` while the
background is 20.1 from the eye, and the measured extents shrink from ±7.07 × −27…0.07 to ±0.05.

**Fix direction:** split "frame target and distance" from "measure scene". Frame Selection should
set target/distance from the subtree box but keep `sceneMin/sceneMax` and clip planes derived from
the scene (or the union of scene and subtree). Fixes R5 at the same time.

**Required regression:** two meshes 10 units apart, frame the small one: `zfar` exceeds the
distance to the far mesh's farthest corner; `extents` equal the scene extents before framing;
rendered image contains the far mesh's pixels.

## Runs on main's current working tree

Main is under active edit, so its working tree was copied (rsync, no `.git` changes) to a scratch
checkout and built there with its own DerivedData; nothing on main was built or modified.

- `CriticalReviewRegressionTests` (7 probes, R4/R6/R7×2/R8/R10/R12): **all 7 fail as predicted** at
  review time. Existing `GizmoHitTests`, `AnimationSamplerTests`, `FrameSelectionTests`: 16/16
  pass — they do not cover these cases.
- `CriticalReviewRegressionTests2` (6 probes, R1/R2/R3/R5/R9/R15): **all 6 fail as predicted**; the
  R9 control (mesh pick returns the front quad) passes. Measured: STEP at t = 1 returns 0 and at
  t = 7 returns 10; R5 target `(5.5, 0, 0)` instead of `(10.5, 0, 0)`; R15 values above.
- Probe sources lived in a throwaway worktree (`CriticalReviewRegressionTests*.swift`); they were
  not merged to main. Reintroduce per-finding when fixing.
- The earlier snapshot build blocker (`GLTFAccessor.type`, missing `try`) no longer reproduces.

## App layer (sidebar, inspector, navigation gizmo, window state)

Read from a 14:50 snapshot of main (`ViewState` gained multi-selection, `pick()`, Select
Parent/Children and Hide/Solo Selection during the pass). A2, A3, A6 were replayed in a standalone
script; the others are source traces. A1 and A2 were re-checked against main afterwards.

### A1 · P2 · `activeCameraPreset` survives canvas orbit, so the gizmo jumps to the opposite view

**Location:** `ViewState.swift` (`activeCameraPreset`, cleared only in `fit`/`zoom`/`orbit(dx:dy:)`/
`frameSelection`/file camera), `NavigationGizmo.swift:106–110` (`cameraPreset(for:activePreset:)`),
`ModelView` `drag`/`wheel`/`autoRotateStep` (no callback to `ViewState`).

Click +Z → Front; orbit the canvas 90° with the mouse (or leave Auto-Rotate on); click +Z again →
**Back**, because the stale preset still says Front. The View menu keeps the Front checkmark and
auto-ortho stays on during free orbit.

**Fix direction:** an `onUserCameraChange` callback from `ModelView` that clears the preset, or derive
"already at this preset" from `viewRotation`. Decide whether free orbit drops auto-ortho.

**Required regression:** `show(.front)`, simulated canvas orbit → `activeCameraPreset == nil` and
`cameraPreset(for: .posZ, …) == .front`.

### A2 · P2 · Vertical gizmo drag orbits opposite to a canvas drag

**Location:** `NavigationGizmo.swift:195` (`dy = start.y - value.location.y`) vs `ModelView.drag`.

`ModelView` computes the same expression from AppKit window coordinates (y up), giving a y-down
delta. SwiftUI `DragGesture` locations are already y-down, so the gizmo's `dy` has the opposite
sign. Replayed through `MetalUserCamera.orbit`: a 10 pt downward drag gives `ΔrotX = −0.0556` on the
canvas and `+0.0556` on the gizmo.

**Fix direction:** `dy = value.location.y - start.y` (or invert both axes if a trackball feel is intended).

**Required regression:** pure drag-to-delta function; downward drag yields the same `rotAroundX` sign
for gizmo and canvas.

### A3 · P2 · Rows from inactive scenes can be selected, hidden, soloed and framed

**Location:** `OutlinerSection.swift:80` (lists every scene's roots), `OutlinerTree.layerVisibility`,
`ViewState` layer/selection setters, `ShapeSection`, `CanvasRegion` readout, `MaterialSection` Used By.

The loader builds only the active scene. Soloing a node from another scene blanks the canvas while
the outliner shows that node visible and the active roots `hiddenByParent`. Selecting it gives an
empty Shape preview, a dimensions readout from `bounds(ofNode:)` (which walks the whole file) and
Frame Selection on empty space. Same family as R6/R7: one "active scene membership" source of truth
is missing.

**Fix direction:** show only the active scene in the Scene section, or mark foreign rows "not in scene"
and refuse layer/frame actions; filter `nodeIndices(usingMaterial:)` and solo/hide input.

**Required regression:** two-scene fixture, scene 0 active: node 1 absent or flagged; `toggleSolo(1)`
refused or does not blank the canvas.

### A4 · P2 · `CanvasRegion.body` re-evaluates every camera frame (60 Hz in auto-rotate)

**Location:** `CanvasRegion.swift:112` reads `view.canvas.viewRotation`; `:132–135` readout calls
`bounds(ofNode:)`; `ModelView.reportOrientation` writes `viewRotation` on every redraw.

Each drag event or display-link tick rebuilds `ViewOptions` (including the material-highlight scan),
runs `updateNSView`, and recomputes the selected subtree's AABB (recursive `worldMatrix` per node) on
the main thread. Compounds R11.

**Fix direction:** read `viewRotation` only inside the gizmo view; cache node bounds per
`(sceneGeneration, nodeIndex)`.

**Required regression:** count `bounds(ofNode:)` calls across a `viewRotation` change (expect 0).

### A5 · P3 · Shape preview resyncs on every option change, resetting its orbit and rendering stills synchronously

**Location:** `ShapeSection.swift:36–40,127–155` (`.onChange(of: view.options)`).

Any exposure/FOV/floor/hide change re-applies and refits the preview, so an orbited preview snaps
back to front on an exposure nudge. With a camera selected, each slider tick re-`adopt`s the scene
and renders a 200 × 200 still on the main actor. `.task(id:)` and `onChange` both fire on selection
change, doubling the work.

**Fix direction:** diff `previewOptions(from:)`; refit only on node/generation change; adopt only on
generation change; coalesce camera stills.

**Required regression:** orbit preview, change only exposure → angles unchanged and no `adopt`.

### A6 · P3 · Shift-click range picks the primary row by kind name, not by the clicked row

**Location:** `ViewState` `selectedIDs` setter / `rowOrder`.

`rowOrder` compares `NodeKind.rawValue` strings, so a range Mesh1…Mesh4 containing a group makes the
group (`"empty"` < `"mesh"`) the inspector's primary row and scrolls the list to it. Replayed:
`shift-click Mesh4 -> primary ID(kind: empty, index: 2)`.

**Fix direction:** primary = most recently clicked row (anchor/far end), ordered by outliner position.

**Required regression:** range including an empty → primary is the far end of the range.

### A7 · P3 · Gizmo acts while the canvas is loading or a file camera is active

**Location:** `CanvasRegion.swift:69,110–116`, `ViewState.orbit`/`show`, `ModelCanvas.readyView`.

The gizmo is live while the renderer is still `.loading` (menu presets are disabled then): a click
sets the preset and ortho, the camera command is a no-op, and the model loads ortho with "Top"
checked. `ViewState.orbit` does not clear `fileCameraNodeIndex`, so a gizmo drag under a file camera
rotates the hidden orbit camera and the view jumps when the file camera is left.

**Fix direction:** disable the gizmo unless `canvas.phase == .ready`; clear the file camera in `orbit`.

**Required regression:** not-ready `show(.top)` leaves state unchanged; `orbit` clears `fileCameraNodeIndex`.

### A8 · P3 · Shape preview retains a stale `MetalScene` and shows a blank box for mesh-less empties

**Location:** `ShapeSection.swift:78,86–91,111–117`, `ViewState.reset()`, `Inspector` (`ShapeSection` for `.empty`).

The preview's renderer keeps its adopted scene until a mesh/camera is selected after a generation
change, so a variant/scene switch with a material selected keeps the old GPU buffers alive. Joints
and other empties without mesh descendants get an empty 200 pt preview. `reset()` also leaves
`showsSceneGizmos` and `lastPick` set.

**Fix direction:** release the preview scene on reset/selection change; show the section only when
the node has draws.

**Required regression:** weak reference to the old scene becomes nil after a swap; joint selection
shows no interactive preview.

Lower confidence, not written up: ⌘↑/⌘↓ (Select Parent/Children) override the List's own ⌘-arrow
navigation; menu Hide Selection stays enabled for `hiddenByParent`/`hiddenInFile` rows while the
context-menu Hide is disabled; nothing shows which node is soloed.

## Pass 3 — animation transforms, GPU morph, material highlight (completed 13:39–14:34)

Leaves: `rc2v1tsr` clips/pose, `q9fppsgo` per-frame node transforms, `z8bzuhwz` GPU morph,
`g7bd2y5a` material highlight; `bi329hbl`/`huj04ed6` read as provisional. Read-only on main; pure
math replayed in a scratch script. M01 and M02 re-checked against source by the review lead
(skin bake `MetalSceneLoader.swift:184` precedes `gatherMorph` `:264`; `MetalRenderer.pick` at `:139`
has no `animationPose` parameter).

Checked and correct: `T*R*S` composition (exact vs gl-matrix), dirty re-derivation of children and
off-scene joints, matrix-authored nodes, inverse-transpose normals under non-uniform scale,
per-frame `negativeScale` with front-face flip in draw and pick, all-zero weights take the rigid
path, MSL morph indexing matches `gatherMorph`, sparse morph accessors via GLTFKit2.

### M01 · P1 · Morph deltas are applied after the CPU skin bake (spec: morph, then skin)

**Location:** `MetalSceneLoader.swift:184–206` (skin bake), `:264` (`gatherMorph` on raw deltas),
`pbr.metal:45–51` (deltas added to skinned position/normal/tangent); `boundsVertices` `:269–279`.

The old loader baked morph before skinning; the new one removed that, so deltas are never skinned.
Joint rotated 90° about Z, vertex (1,0,0), delta (0,1,0), weight 1: spec R·(v+d) = (−1,1,0), new
R·v+d = (0,2,0). Every skinned character with blendshapes (facial rigs, VRM) is wrong whenever a
weight is non-zero, including at rest with non-zero default weights.

**Fix direction:** skin after morph on the GPU (huj04ed6), or until then bake each delta through
the per-vertex blended matrix (w = 0; inverse-transpose for normal deltas). Don't ship 6.3b alone.

**Required regression:** one joint at 90°, one target at weight 1 → captured vertex = R·(v+d).

### M02 · P1 · Picking ignores the animation pose

**Location:** `MetalRenderer.pick` (`:139`, no pose → rest transforms), `encodePick`
(`morphWeights(for:pose: nil)`), `ModelView` click path.

With playback wired (`ModelCanvas.swift:246`), pause BoxAnimated at t = 0.5: clicking the drawn inner
box hits background; clicking its rest position selects it. Morphed silhouettes pick at rest weights.

**Fix direction:** thread `animationPose` through `pick`/`gizmoPickFrame` → `sceneFrameSetup` →
`encodePick`, fed from `animationPoseProvider`.

**Required regression:** BoxAnimated at 0.5: posed pixel → inner node; rest pixel → not inner node.

### M03 · P2 · Overlays, bounds, framing, gizmos, file cameras and lights stay on the rest pose

**Location:** `MetalScene.worldMatrix`/`bounds(ofNode:)`/`fileCamera` (walk `node.matrix`); lights baked
once in the loader; consumers in `MetalOverlays` and `ModelView.frame(nodeIndices:)`.

During playback the selection, hover and material boxes, skeleton lines and gizmos stay put while
the mesh moves; Frame Selection frames the rest position; animated file cameras and lights (or ones
under animated parents) don't move. Same root as M02: only `drawTransforms` sees the pose.

**Fix direction:** compute posed node worlds once per frame (reuse the `drawTransforms` walk) and
route overlays, bounds, gizmo hits, file cameras and per-frame light positions through it.

**Required regression:** pose at 0.5 → selected AABB moves by the animated translation; a light
under an animated node changes position in the GPU light array.

### M04 · P2 · Generated normals/tangents are frozen at the unmorphed shape; a test locks it in

**Location:** `MetalSceneLoader.swift:241–258` (face normals, MikkTSpace from rest positions),
`pbr.metal:143` (derivative fallback only for a zero normal), `MetalMorphTests.swift:112–113`.

`morph-triangle.gltf` has no NORMAL: at weight 1 the moved vertex keeps the rest normal. Khronos
uses screen-space derivatives without `HAS_NORMAL`, which follow the morph. Files with non-zero
default weights and no NORMAL now shade differently from before the change (regression at rest).

**Fix direction:** with POSITION targets and no NORMAL (or TANGENT), emit zero vectors so the shader
takes the derivative path; invert the test.

**Required regression:** morph-triangle at weight 1 → shaded normal equals the morphed face normal;
pixel reference with non-zero defaults and no NORMAL matches pre-change output.

### M05 · P2 · Morph buffers are dense per de-indexed vertex and per instance; shader loops every target

**Location:** `MetalSceneLoader.swift:312–345` (`slots × targets × emittedVertices` float4),
`:121–124` (`append` per GPU instance), `pbr.metal:24–30` (`morph_sum` over all targets),
`MetalRenderer.swift:603–605` (`makeBuffer` per draw per frame above 4 KB of weights).

A 20k-vertex face de-indexed to 120k corners with 52 POSITION+NORMAL targets needs ≈ 200 MB
(arithmetic, not measured) versus ~25 MB of source; instancing multiplies it and allocation failure
now fails files that loaded before. Every vertex reads targets × slots even with one weight set.

**Fix direction:** store deltas per source vertex indexed through `sourceOf`; share across instances;
pass a compact active-target list; ring-buffer large weight arrays.

**Required regression:** `morphBuffer.length == slots × targets × sourceVertexCount × 16`; two
instances share one buffer (`===`).

### M06 · P2 · Material highlight ignores variants, the active scene and hide/solo

**Location:** `GLTFDocument.swift:212–219` (base `primitive.material` only), `ViewState.swift:367–370`,
`MetalOverlays.swift:158–161`.

With a `KHR_materials_variants` variant active, the variant material outlines nothing and the base
material outlines meshes that no longer use it. Nodes from other scenes get floating boxes; hidden
or solo'd-out meshes still get boxes. Same family as R7/A3.

**Fix direction:** resolve users through the active variant mapping; restrict to drawn-scene,
visible, non-hidden nodes.

**Required regression:** variant selected → highlight reflects the mapped material; hidden and
other-scene nodes emit no AABB vertices.

### M07 · P3 · Material-highlight box covers the whole subtree, not the primitives using the material

**Location:** `MetalOverlays.swift:344–350` → `bounds(ofNode:)` (subtree).

Body uses X, child wheels use Y: highlighting X boxes body + wheels; parent and child both on X give
nested boxes; a multi-material mesh is boxed whole.

**Fix direction:** node-local `bounds(ofNode:primitivesUsing:)` from per-primitive accessor min/max.

**Required regression:** parent/child with different materials → box equals the parent's own primitive bounds.

### M08 · P2 · (provisional, bi329hbl) Clips re-parse the file on the main actor and skip meshopt decoding

**Location:** `ModelCanvas.swift:214–237` (called from `sync()` `:347`, `@MainActor`);
`AnimationClip.matrixAuthoredNodeIndices` reads the whole file, twice.

A second full `GLTFAsset(url:)` parse plus raw reads run on the main thread after load (UI stall).
The clip loader bypasses `MetalMeshoptPreprocessor`, so `gltfpack -cc` files with compressed samplers
lose their animation or sample garbage.

**Fix direction:** build clips in `MetalSceneLoader` from the same decoded asset, off-main; take
matrix flags from the JSON the loader already holds.

**Required regression:** gltfpack-compressed animated fixture → clips equal the uncompressed file's.

### M09 · P3 · (provisional) Animating a skinned mesh's own node moves the baked skin

**Location:** `MetalPose.swift:84–91` applies `worlds[node]` to every draw; skin bake used
`inverse(model_rest)·J·IB`.

The spec ignores a skinned mesh node's transform. Animating that node (or a non-shared ancestor)
draws `model_posed·model_rest⁻¹·J·IB`; the common shared-armature case cancels, hiding the bug.

**Fix direction:** keep skinned draws on the rest model now; identity + `J_posed·IB` in huj04ed6.

**Required regression:** animate the mesh node of a skinned fixture → draw transform unchanged.

### M10 · P3 · (provisional) Turntable ignores the pose; paused t = 0 shows rest, not the first key

**Location:** `ModelView.swift:270` (`turntable` → `renderer.image` without pose),
`ModelCanvas.swift:181` (`if !isPlaying, time == 0 { return nil }`).

Pausing mid-clip and exporting a turntable renders the rest pose (PNG export does pass the pose).
Scrubbing to 0 shows rest TRS, so the frame jumps between 0 and 0.001.

**Fix direction:** pass the pose provider in `turntable`; use an explicit stopped flag.

**Required regression:** turntable frame 0 equals `snapshot()` when paused at 0.5.

**Done-when status:** `rc2v1tsr` met (no new defects). `q9fppsgo` met for drawing; pose does not reach
pick/overlays/bounds (M02/M03). `z8bzuhwz` only partly met: its Result says pixel refs are "pending
confirm", and the old-bake parity holds for positions only (M01, M04). `g7bd2y5a` unit tests met; no
on-screen check recorded; M06/M07 gaps.

## Pass 4 — Viewer essentials (`3pk4ibv6`, completed 14:13; committed in `c40b96a`)

Main committed the scene-interaction work as `c40b96a` and `e8b67d2` during this pass; line numbers
are for that HEAD. Camera math replayed standalone; the rest traced. V01 re-checked by the review
lead (`ModelView.wheel` `:636–646`: orthographic takes plain `zoomBy`, no `applyProjection`).

### V01 · P1 · Wheel/pinch zoom does nothing in axis views, then the next orbit jumps

**Location:** `ModelView.swift:636–646`, `MetalUserCamera.zoomBy` `:85–93`, `applyProjection`.

`zoomBy` changes `distance` but not `orthographic.magnitude`, and the ortho path never calls
`applyProjection`. Since `ggq8r9uj` makes every axis click orthographic: click Front, scroll — image
unchanged, zoom % climbs; next orbit returns to perspective at the accumulated distance (often inside
the model). Replayed: ten `zoomBy(-5)` → magnitude stays 2.071, distance 5 → 0.156.

**Fix direction:** in ortho, restate/scale the magnitude after the dolly and apply the same pointer
shift so zoom-toward-pointer works there too.

**Required regression:** Front preset + wheel step → magnitude shrinks; orbit → perspective distance
matches the zoomed framing.

### V02 · P1 · Orbit-around-selection (default on) re-aims the camera on every selection and breaks click-cycle

**Location:** `ModelView.swift:121–124,570–598` (`retarget`), `ViewState.pick` `:185–198`.

Each primary-selection change glides the selected box centre to screen centre with the eye fixed,
so the clicked part slides from under the pointer. A second click at the same pixel hits something
else, `lastPick.hit == nodeIndex` fails and the parent walk never happens; a click within 0.25 s
cancels the glide half-way; ⌘/⇧ toggles re-aim at each added node.

**Fix direction:** keep a pivot and orbit around it only when a drag starts (Blender); at minimum
don't retarget for canvas picks or toggles.

**Required regression:** `orbitsAroundSelection` on, two clicks on the same point over an off-centre
child → parent selected and the view matrix unchanged by selection.

### V03 · P2 · Selecting in an axis/ortho view tilts it off-axis and rescales it, preset still shown

**Location:** `MetalUserCamera.retargetKeepingEye` `:99–111`, `ModelView.swift:580–593`, `ViewState.swift:330–337`.

Front view, click a part at (4,0,4): azimuth 0° → −33.7°, magnitude 4.14 → 2.99 (replayed). The
gizmo and View menu still say Front; auto-ortho stays on. Same "camera changes invisible to
ViewState" root as A1.

**Fix direction:** in ortho keep magnitude and look direction and pan the target, or skip retarget;
report camera moves so the preset clears.

**Required regression:** ortho retarget keeps `orthographic.magnitude` and the axis-aligned look direction.

**V04** (hover/click pick and turntable ignore the animation pose) is the same defect as M02/M10;
see there. Hover makes it visible while paused.

### V05 · P2 · Turntable re-reads the live camera each frame; selection boxes are baked in

**Location:** `ModelView.swift:263–266`, `ViewState.swift:345–353`.

Angles are captured once but `distance`/`target` are re-read after each `await` while the UI stays
interactive, so a zoom, pan, selection (which starts a glide) or an in-flight glide bends the rest of
the orbit. Full `options` are used, so selection/highlight boxes appear in every frame. No progress, no cancel.

**Fix direction:** snapshot pose and pose provider before the loop; strip selection/highlight/hover
from export options; progress with Cancel; block canvas input during export.

**Required regression:** change the canvas camera between frame callbacks → frames still form one orbit.

### V06 · P2 · A failed turntable export deletes the old file, leaves a partial one, and says nothing

**Location:** `TurntableExport.swift:43` (`try? removeItem` before rendering), `:72–75` (log only);
`MP4Encoder` has no `cancelWriting`.

Overwrite `x.mp4`, a frame fails (GPU error, `noScene` after reload): the original is gone, a corrupt
partial file remains, the writer is dropped mid-write, and the user sees nothing. PNG export also only logs.

**Fix direction:** write to a temp file beside the destination and replace atomically; on error
`cancelWriting()` and remove the temp; show an alert.

**Required regression:** encoder throws mid-stream → destination keeps its original bytes, no temp left.

### V07 · P3 · X-ray depends on file order; Mask and transmission wrong under X-ray; clay keeps vertex colour

**Location:** `MetalRenderer.swift:713` (opaque list unsorted), `:447–458`, `MetalDrawStyle.swift:48–52`.

X-ray blends every draw without depth writes but leaves opaque draws in file order, so a far mesh
listed later draws over a near one. `flags.y = 2` drops the Mask cutoff (cut-out cards become faint
quads). The transmission prepass still uses normal shading. Clay multiplies by COLOR_0.

**Fix direction:** sort all draws back-to-front in X-ray, keep the Mask discard, pass the style to the
prepass (or skip it); ignore vertex colour in clay.

**Required regression:** two overlapping quads in reversed file order → identical X-ray image.

### V08 · P3 · Every hover pick allocates full-size GPU targets and waits on the main thread

**Location:** `MetalRenderer.swift:147–171`, `ModelView.swift:665–695`, `:536–560` (`pointerWorldPoint`).

Up to 15 hover picks/s, each a full-resolution r32Uint + depth32 (~59 MB at 5K) and a full render with
`waitUntilCompleted`; gizmos add a second `sceneFrameSetup`; every wheel event runs one just for the
view-projection. Extends R11.

**Fix direction:** cache pick targets or render a 1×1 region (scissor + projection jitter); compute the
view-projection from `MetalCamera` directly.

**Required regression:** pick reuses its textures (allocation count), or 1×1 pick equals full-size pick.

### V09 · P3 · Hover may pick through the glass sidebar and inspector (needs on-screen check)

**Location:** `ModelView.swift:667` excludes only the title-bar band, not `contentInsets.left/right`.

The canvas runs full-bleed under both panes with an `.inVisibleRect` tracking area, so moving over the
outliner can hover-pick the mesh behind it, tinting another row and showing a tooltip under glass.

**Fix direction:** clear and skip hover inside the side insets.

**Required regression:** non-zero `contentInsets.left`, move inside it → `onHover(nil, nil)`.

### V10 · P3 · Dimensions readout overstates rotated parts and ignores multi-select

**Location:** `CanvasRegion.swift:122–129`, `MetalScene.bounds(ofNode:)`.

World-axis box of transformed corners: a 2×1×1 part rotated 45° about Y reads 2.12×1×2.12. With
several nodes selected, only the primary is measured while F frames the union.

**Fix direction:** local box × world scale for one node (or label it "world bounds"); union for a selection.

**Required regression:** 45° child → 2×1×1 (or an explicit world label); two-node selection → union.

### V11 · P3 · Totals double-count vertices when primitives share a POSITION accessor

**Location:** `GLTFDocumentJSON.swift:357`, summed in `GLTFDocumentTotals.swift:64`.

`POSITION.count` is added per primitive; exporters that split by material while sharing one POSITION
accessor get that count once per primitive.

**Fix direction:** count distinct POSITION accessors per mesh.

**Required regression:** two primitives sharing one POSITION → `vertexCount` equals the accessor count.

**Done-when status:** met — `1cxtu56y` (world bounds, V10), `advg8yaq` (V07), `cm2j1flm` (no problems),
`mdleya4f` (V11), `vn4trm11` (consistent; V02 side effect), `yel6vru3` (V04/V08/V09). Literal only —
`ggq8r9uj` (V01, V03). Partly — `lf9s93sq` (perspective zoom-to-pointer correct, ortho fails; V02/V03).
**Not met with defaults** — `lusha0c3` (V02). `swrmm3ku`: frame count/duration tested, Quick Look
playback never checked; V05/V06.

## Pre-implementation notes for `huj04ed6` (GPU skinning), 2026-11-04 ~15:50

Written while the ticket was in progress and before any loader or shader edits were on disk. The
brief's shader formulas (`p = skin·pos` with no model matrix, the mesh node's normal matrix on
`skinN·n`, `model·(skin·t)`) match research §2 and are the Khronos quirks, so this resolves M09.
The risks are in what else must change when the CPU bake is removed:

1. **Every pipeline needs the skin constants, not just the colour pass.** `MetalRenderer` keeps
   three caches keyed only by `morphMask`: `pipeline` (`:533`), `pickPipeline` (`:521`) and
   `capturePipeline` (`:558`). The transmission prepass and X-ray styles go through `pipeline`.
   Today the CPU bake makes pick and capture correct for free. Once skin is GPU-only, any pass that
   doesn't bind `hasSkin` and the joint buffer draws skinned meshes as raw bind-space positions
   with no model matrix: wrong place, wrong pick, wrong capture. Add `hasSkin`/`hasJoints1` to all
   three keys, and bind joints in `encodeScene`, `encodePick` and the capture encoder.
2. **Picking needs the posed joints too (M02).** `pick` and `encodePick` pass `pose: nil`. With GPU
   skinning that means bind or rest joints, while the canvas draws the posed ones. Thread
   `animationPose` through `pick` → `sceneFrameSetup` → `encodePick` in the same change, or
   skinned characters become unclickable during playback.
3. **Morph before skin (M01).** In `khronos_vertex`, add the morph deltas to `pos/nrm/tan` before
   applying `skin`/`skinN`. Defined test 2 already asserts this. Remove the CPU skin bake and the
   post-skin morph in the same commit.
4. **Rest bounds.** `boundsMin/Max` come from the baked vertices. Keep a one-off CPU skin for them,
   applying morph first, then skin, as in M01. `bounds(ofNode:)` uses accessor min/max and is
   unaffected; Frame Selection on a skinned mesh therefore still boxes the bind-space accessor
   range × mesh world, which is the existing Khronos `subtreeAABB` behaviour.
5. **Joints outside the scene / joint-count limits.** Joint worlds must come from the same posed walk
   (`drawTransforms`) that already re-derives off-scene joints; `> 32` joints need a real buffer
   (the brief says so). Bind it at the same index in all passes from item 1.
6. **Rest-path identity.** With `hasSkin` false the rigid pipeline must be byte-identical, so the
   pixel refs stay green. Skinned reference files (`rigged`, Fox, CesiumMan) will move by float
   noise only if the CPU and GPU blends differ. Compare against the CPU bake within 1e-5 before
   trusting the refs.

## Pass 5 — playback model (`bi329hbl`) and timeline HUD (`sygpfhz7`)

6.4a is in `c40b96a` plus an uncommitted `ModelCanvas.swift` diff; 6.4b is uncommitted. The
playback logic (`play`/`tick`/`applyTimeDelta`, `wrappedAndClampedTime`) was replayed standalone.
H01 and H06 were re-checked by the review lead (`play()` at `ModelCanvas.swift:131` has no rewind;
`AnimationPlaybackTests` discards `waitUntil` results with `_ =`).

Checked and correct: no jump on pause/resume; wall-clock × speed advance (no frame-rate drift);
loop wrap handles large deltas; playback and auto-rotate share one display link; the link is
invalidated off-window and at a non-loop end, with weak closures; `reset()` stops playback; a URL
change resets clips and time; stale poses are index-guarded; sidebar rows map 1:1 to clips; 60 Hz
invalidation stays inside `DSTimeline` except H08; Quick Look stays at rest; accessibility labels exist.

### H01 · P2 · Play does nothing after a non-looping clip ends

**Location:** `ModelCanvas.swift:131` (`play`), `:239–253` (`applyTimeDelta`).

With loop off, playback stops at `time = duration`; `play()` doesn't rewind, so the next tick
stops again. Play and Space only flicker until the user scrubs back. Same after switching to a
shorter clip while paused past its end. Replayed: 2 s clip → `time=2.0 playing=false` after Play + tick.

**Fix direction:** rewind in `play()` when `!loops && time >= playbackDuration`; clamp `time` when the selection changes.

**Required regression:** loop off, past the end, `play()`, advance 0.1 → playing, `time ≈ 0.1`.

### H02 · P2 · Scrubbing while playing fights the drag

**Location:** `DSTimeline.swift:66–80` (no `onEditingChanged`), `ModelCanvas.swift:146` (`scrub` keeps playing).

Holding the thumb still lets the clip run on under the cursor (replayed: 1.017, 1.033, 1.05 … with
the drag held at 1.0); with loop off it can stop mid-drag.

**Fix direction:** `isScrubbing` set from `Slider(onEditingChanged:)`; skip ticks while set; resume from the release time.

**Required regression:** play, begin scrub, advance clock, tick → time unchanged; end scrub → advances.

### H03 · P2 · With loop off, shorter clips still loop and stop at the wrong pose

**Location:** `AnimationSampler.swift:98–109` (per-clip wrap), `ModelCanvas.swift:217` (global = longest clip).

With clips of 1 s and 3 s and loop off, the short clip restarts at t = 1.33 (samples 0.33); the
stopped frame shows it mid-cycle (1 s + 2.5 s → samples 0.5 instead of 1.0). Scrubbing has the same issue.

**Fix direction:** when not looping, evaluate each clip at `min(time, clip.maxTime)` (a `wraps` flag on
`AnimationPose(clips:at:)`); keep per-clip wrap for loop mode.

**Required regression:** 1 s and 3 s clips, loop off, t = 2 → short clip's pose equals its t = 1 pose.

### H04 · P2 · "All" is the disjoint default set, so the clip picker misreports what plays

**Location:** `DSTimeline.swift:86,108–119`, `ModelCanvas.swift:167`, `AnimationClip.swift:34`.

"All" maps to `defaultSelectedClipIndices` (first-come disjoint clips). On Fox (Survey, Walk, Run
on one rig) "All" plays only Survey, and choosing Survey shows the title "All". No checkmarks.

**Fix direction:** rename the entry ("Default"), or track an explicit selection; checkmark the current
item; show the clip name when exactly one clip is active.

**Required regression:** three same-target clips, select 0 → title is the clip name.

### H05 · P2 · Timeline overlaps the dimensions readout at normal canvas widths (needs on-screen check)

**Location:** `CanvasRegion.swift:119–127,159–161`, `DSTimeline.swift:35`.

Side clearance is sized for the gizmo (108 pt each side), but the bottom-trailing readout is ~180 pt
or wider and shares the bottom inset; the 520 pt HUD overlaps it below ~910 pt of canvas width, which
is typical with both panes open. Below ~540 pt `minWidth: 320` pushes into the gizmo. The leaf's
Result says on-screen was deferred.

**Fix direction:** measure the readout for trailing clearance, or move the readout above the timeline while clips exist.

**Required regression:** `CanvasRegion` at 800×600 with an animated fixture → HUD and readout frames
don't intersect; light/dark screenshots.

### H06 · P2 · Display-link and reload tests can't fail; HUD tests bypass the controls

**Location:** `AnimationPlaybackTests.swift:19,117,122,132,144–155`; `TimelineHUDTests.swift:16,38–68,99–111`.

`waitUntil` returns false on timeout and every call is `_ = try await waitUntil {…}`, so
`displayLinkRunsOnlyWhilePlayingOrAutoRotating` passes even if the link never starts or stops (after a
30 s wait). HUD tests call `canvas.play()` and set properties directly instead of pressing hosted
controls; Space, the sidebar Animations row, the animated-row indicator and live morph weights are untested.

**Fix direction:** `#expect(try await waitUntil {…})` (or `#require`); drive hosted controls via AX press/increment.

**Required regression:** temporarily make `updateDisplayLink` never invalidate → the test fails.

### H07 · P3 · Zero-duration selections play forever; time can sit past the clip end

**Location:** `ModelCanvas.swift:103,131,239–244`.

`play()` only checks that clips exist. A zero-duration clip (reachable from its sidebar row) makes
time grow without bound at 60 Hz (replayed: 10 s of ticks → `time=10.0 playing=true`). Switching from
3.5 s on a 4 s clip to a 1 s clip shows `00:03.50 / 00:01.00` with an out-of-range slider.

**Fix direction:** guard `playbackDuration > 0` in `play()`; clamp `time` on selection change.

**Required regression:** zero-duration clip, `play()` → not playing, link inactive.

### H08 · P3 · Live morph weights re-render the whole Inspector at 60 Hz and miss node weights

**Location:** `Inspector.swift:113–118`, `FactSections.swift:144–160`.

`sections(for:)` reads `currentAnimationPose()` inside `Inspector.body`, so a selected morph during
playback re-evaluates the whole Inspector and every active channel each frame on the main thread.
It reads only `meshWeights`, so files whose weights channel targets node-authored weights show no live values.

**Fix direction:** a small child view that reads the pose; look up `nodeWeights[node]` first; reuse the renderer's per-frame pose.

**Required regression:** node-authored-weights fixture at mid-clip shows numeric weights.

### H09 · P3 · DSTimeline breaks Design System layering; keyboard scrubbing is coarse

**Location:** `DSTimeline.swift:1,22,35,52–80`, `DSOutlineRow.swift:89–94`.

The only DS component that imports `Renderer`; depends on app-layer `OverlayMetrics.timelineHeight`;
raw `Slider` with magic widths and fonts. `step: 0.01` snaps to 10 ms (1/30 s and 1/24 s keys can't
be hit); arrows move 0.01 s per press.

**Fix direction:** plain labels and a height token; a DS scrubber with `step: nil`, key snapping and
~1/30 s and 1 s adjustable-action steps.

**Required regression:** AX increment moves one frame step; the DS component builds without `import Renderer`.

**Done-when status:** `bi329hbl` partly met — defined test 3 is vacuous (H06), no-loop and
zero-duration behaviour wrong (H01, H03, H07). `sygpfhz7` **not met** — the required UI test of play and
scrub through the controls and the light/dark on-screen screenshots are missing ("On-screen deferred");
whether Space reaches `.onKeyPress` while `ModelView` is first responder is unverified.

## Provisional — animation clip/pose (in progress, not yet wired to the renderer)

These read `Renderer/Scene/AnimationClip.swift`, `AnimationPose.swift`, `AnimationChannelTarget.swift`
as they are on main now. Nothing outside tests calls them yet; re-check when integrated.

### P-A1 · P2 · Morph-weight animation is dropped when the mesh has no authored default `weights`

**Location:** `AnimationClip.swift:113–141`.

The weights channel's component count comes from `node.weights?.count ?? mesh.weights?.count ?? 0`.
`mesh.weights` is optional in glTF; the morph target count is `primitive.targets.count`. A mesh
with targets but no default weights gets `componentCount == 0`, and `AnimationSampler.evaluate`
returns `[]`, so the animation silently never plays.

**Fix direction:** use the first primitive's `targets.count` (and validate it matches across
primitives); keep `weights` arrays only as defaults.

**Required regression:** mesh with two morph targets, no `weights` on mesh or node, LINEAR weights
animation → pose contains two weights at t = mid.

### P-A2 · P2 · A malformed sampler crashes the process through `precondition`

**Location:** `AnimationSampler.swift:46`; no count check in `AnimationClipLoader.sampler(from:)`.

`evaluate` asserts `output.count == input.count × stride`. The loader never checks it, so a file
whose output accessor is short or long (or whose weight count disagrees with `node.weights`)
traps the app — or the Quick Look extension — on first evaluation instead of reporting an error.

**Fix direction:** validate in the loader and throw `AnimationClipError.mismatchedSampler`; keep
`evaluate` total (return `[]` or clamp).

**Required regression:** sampler with 3 input keys and 2 VEC3 outputs → `loadClips` throws.

### P-A3 · P3 · All pointer channels share one target key, so disjoint pointer clips exclude each other

**Location:** `AnimationChannelTarget.swift:47–48` (`.pointer` → `(translation, nodeIndex: -1)`).

`defaultSelectedClipIndices` treats every `KHR_animation_pointer` channel as the same target (and
as a "translation"). Clip B is dropped whenever clip A has any pointer channel, even when they
animate different materials.

**Fix direction:** give pointer targets their own key case carrying the pointer string.

**Required regression:** two clips animating `/materials/0/…` and `/materials/1/…` → both selected.

### P-A4 · checked, not a defect · normalized integer outputs

GLTFKit2's `GLTFTransformPackedDataToFloat` (`GLTFAsset.m:170`) applies the spec's
`max(c / 127, -1)`-style divisors when `isNormalized`. No action; a normalized-SHORT rotation test
would still be cheap insurance.

## Review-only build accommodations

The stable snapshot caught two unfinished integration errors. To run completed-renderer regression
probes, the review worktree alone was adjusted to use GLTFKit2's `accessor.dimension` API and make
`ShapePreviewSyncKey` Equatable (its options are not Hashable). These two changes are not fixes to
review findings and were not applied to main. The original build failure log is retained. Any
subsequent test result must be read with this qualification.
