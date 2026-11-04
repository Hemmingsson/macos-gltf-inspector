# Critical implementation review — 2026-11-04

Working handoff for improving the renderer port and scene-interaction implementation. Findings are
being added and verified as the review proceeds. This is a review, not a patch or merge approval.

## Review scope and evidence

- Baseline: main HEAD `dbc169fc21a23d4ca63e6a32c3d11001ca60f302` plus uncommitted work captured in
  `.worktrees/implementation-review` (`codex/implementation-review`).
- Snapshot provenance, captured backlog, and logs:
  [review evidence](2026-11-04-implementation-review/).
- Completed work under review: visibility/filtering, GPU picking, click routing, reveal/frame,
  navigation gizmo, camera/light gizmos and hit testing, skeletons, shared scenes, animation sampler.
- Shared-scene preview, inspector facts, and clip/pose work were also present but actively being
  implemented. Their observations are provisional and must be checked against their finished code.
- Historical tickets for removed renderers are not current implementations. Worktree-only TDD
  tests remain separate from main's implemented features.
- Product sources on main have not been changed by this review.

## Summary for the handoff (priority order)

| ID | P | Defect | Probe |
|----|---|--------|-------|
| R15 | P1 | Frame Selection re-measures the scene: rest of model far-clipped, floor/gizmos resize | red |
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
| R13, R14, A5–A8, P-A3 | P3 | O(n) index lookups, cycle guards, preview resync/retention, range primary, gizmo while loading, pointer keys | traced |

Common roots worth fixing once rather than per finding:
1. **No single "active scene membership + effective visibility" resolution** (R6, R7, A3, part of R12).
   Build it once in `MetalScene` and reuse for draws, overlays, picking, outliner and inspector.
2. **`MetalUserCamera.fit` serves both whole-scene fit and selection framing** (R4, R5, R15).
   Split target/distance framing from scene measurement and clip-plane fitting.
3. **Picking does not share the render's visibility rules** (R2, R3, R9, R10). Give the pick pass
   depth for every draw and test gizmo hits against it.
4. **Camera state changes in `ModelView` are invisible to `ViewState`** (A1, A7) and **every redraw
   re-renders from scratch and invalidates SwiftUI** (R11, A4).

## Confirmed findings

### R1 · P2 · STEP sampling returns the previous value at exact keys and after the channel ends

**Location:** `Renderer/Scene/AnimationSampler.swift:48–57,111–120`.
**Task:** `ifz67ezm` (completed).

The sampler finds the first key at or after `t`, then STEP always returns the key before it.
For keys `[0,1,2]` and values `[0,10,20]`, sampling at `1` returns `0`; sampling at `7` in a
10-second clip clamps to the final key and returns `10`, so the channel never holds its final
value. This violates exact-key and endpoint behavior.

**Verified:** compiled the real sampler source in a standalone Swift harness; output is in
[pure-reproductions.log](2026-11-04-implementation-review/pure-reproductions.log).
The [glTF interpolation specification](https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html#interpolation)
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

Main has moved since the snapshot: `MetalOverlays`, `MetalRenderer`, `ModelView`, `ViewOptions`,
`ViewState`, `DocumentWindowModel`, the inspector sections and several tests differ from
`.worktrees/implementation-review`. This pass reads **main's current working tree** (read-only).
Main keeps changing during the review (e.g. `ModelView.frame(nodeIndices:)` was added mid-pass);
line numbers are as read and may drift by a few lines — function names are the stable anchor.
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

- `CriticalReviewRegressionTests` (7 probes, R4/R6/R7×2/R8/R10/R12): **all 7 fail as predicted**.
  Existing `GizmoHitTests`, `AnimationSamplerTests`, `FrameSelectionTests`: 16/16 pass — they do not
  cover these cases. Log: [main-tree-probes-1.log](2026-11-04-implementation-review/main-tree-probes-1.log).
- `CriticalReviewRegressionTests2` (6 probes, R1/R2/R3/R5/R9/R15): **all 6 fail as predicted**; the
  R9 control (mesh pick returns the front quad) passes. Measured: STEP at t = 1 returns 0 and at
  t = 7 returns 10; R5 target `(5.5, 0, 0)` instead of `(10.5, 0, 0)`; R15 values above.
  Log: [main-tree-probes-2.log](2026-11-04-implementation-review/main-tree-probes-2.log).
- Both probe files live in `.worktrees/implementation-review/GLTFInspectorTests/`
  (`CriticalReviewRegressionTests.swift`, `CriticalReviewRegressionTests2.swift`). Each expectation
  states the correct behaviour, so they are the red half of red → green for the fixes. Move them
  into the owning task's branch when fixing; they are not on main.
- The earlier snapshot build blocker (`GLTFAccessor.type`, missing `try`) no longer reproduces:
  main's current tree compiles the test target.

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
