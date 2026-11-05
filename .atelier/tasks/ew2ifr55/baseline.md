# Executable backlog TDD baseline — 2026-11-04

**31 test functions added; 10 fail and 21 pass in the isolated baseline.** Full command: `./scripts/dev.sh test` (exit 65): 178 tests in 40 suites; 10 failing new test functions plus the existing feature-reference test, 14 total issues (11 new assertions and 3 reference issues). The 10 new failing tests produce 11 assertion failures. All Khronos sample references pass. The existing feature-reference test adds 3 issues for two overlay regressions (selection and all-overlays); inspected PNGs show the missing cyan selection AABB. Reference files remain unchanged.

Authoritative test location: `/Users/mattias/dev/glb-preview/.worktrees/tdd-backlog-tests` on branch `codex/tdd-backlog-tests`. The worktree contains a snapshot of existing uncommitted feature work plus these tests. Those feature changes are not part of this testing task, and nothing has been committed or merged. Isolation was necessary because active work on main was removing intentional red tests.

Reproduce: `cd /Users/mattias/dev/glb-preview/.worktrees/tdd-backlog-tests` then `./scripts/dev.sh test`. Focus a suite with `-only-testing:GLTFInspectorTests/<suite>`. This branch uses its own DerivedData. The existing ignored Khronos corpus is symlinked from the primary checkout; no fixture/reference content was regenerated.

[Isolated full-run log](proof/isolated-full-test.log) · [Exact source hashes](proof/baseline-isolated.json) · [Archived test sources](tests) · [Initial red evidence](proof/red.log). Source hashes were unchanged through the isolated run. [Inspected reference differences](proof/reference-diffs) show the two inherited overlay regressions. The component harness controls pass; early harness failures and the zero-test-filter trial are excluded from feature evidence. No XCUITest or app launch command was used. Test-owned component windows are closed.

## Failing tests

- `FeatureReferenceTests.everyFeatureMatchesItsKhronosReference()`
- `SceneGizmoTests.selectedJointShowsItsBoneToTheParentJoint()`
- `SceneGizmoTests.skeletonShowsACrossAtEveryJointAsWellAsTheBone()`
- `SceneInteractionComponentTests.animatedFileOffersPlaybackControls()`
- `SceneInteractionComponentTests.emptySelectionShowsSceneGeometryTotals()`
- `SceneInteractionComponentTests.groupSelectionShowsSubtreeGeometryTotals()`
- `SceneInteractionComponentTests.meshInspectorExposesEveryPrimitiveMaterial()`
- `SceneInteractionComponentTests.meshInspectorOffersShapePreview()`
- `SceneInteractionComponentTests.selectingAQuadShowsItsDimensionsInsteadOfTheWholeScene()`
- `SceneSelectionRoutingTests.repeatedMeshHitsCycleThroughParentsAndBack()`
- `SceneSelectionRoutingTests.selectingAUsedMaterialChangesRendererHighlightOptions()`

## Coverage by task

| Task | State | Suite | Observed behavior and remaining cases |
| --- | --- | --- | --- |
| ggq8r9uj | RED → GREEN | AutoOrthographicTests | axisSnapEnablesOrthographicProjection(_:) failed for all six axis presets in red.log (initial main-checkout run) (isOrthographic remained false); it passes in isolated-full-test.log after concurrent implementation. Isometric/reset controls pass. Orbit-return and explicit-ortho cases still need coverage. |
| qtuda1nk | RED → GREEN | SceneInteractionGestureTests | outAndBackOrbitDoesNotBecomeAClick and releasingAModifierBeforeMouseUpDoesNotProduceAnUnmodifiedPick(_:) failed in red.log (initial main-checkout run) (one pick instead of zero), then pass in isolated-full-test.log after concurrent implementation. Plain-click control passes. Backing-scale, title-band and remount cases still need coverage. |
| y3hdxwwh | RED → GREEN | SceneGizmoTests | Selected perspective apex, independently calculated d=0.15 plane/corner/up marker and orthographic near-plane corners all pass in the isolated snapshot after concurrent implementation. Initial main runs recorded actual red. Full global-toggle/active-camera/visibility coverage remains. |
| umczfxl2 | RED → GREEN | SceneGizmoTests | Directional presence/length/-Z direction, all six point-octahedron tips, and spot L×tan(outer) base/ring count pass in the isolated snapshot after concurrent implementation. The earlier main run recorded red. Inner-cone/transformed-light/visibility cases remain. |
| fnaam6pc | RED | SceneGizmoTests | selectedJointShowsItsBoneToTheParentJoint and skeletonShowsACrossAtEveryJointAsWellAsTheBone both fail in the isolated snapshot. The selected joint has neither the required hip-to-knee segment nor the two three-axis crosses. Intermediate-ancestor and multi-skin cases remain. |
| 9toe55f5 | RED | SceneInteractionComponentTests | meshInspectorExposesEveryPrimitiveMaterial fails: Copper is exposed but the second primitive material Rubber is absent. Existing inspector AX control passes. Counts/topology/instancing/joint-of/clickable cross-links remain. |
| mdleya4f | RED | SceneInteractionComponentTests | emptySelectionShowsSceneGeometryTotals and groupSelectionShowsSubtreeGeometryTotals fail: neither exposes the fixture total of 4 tris (3 + 1). Unique asset/instance and other totals remain. |
| hw4fh7zp | RED | SceneInteractionComponentTests | meshInspectorOffersShapePreview fails: selected mesh has no Shape section. Isolation, stable preview identity and no-second-load checks await 0yc5sao4. |
| 2kwjzlmj | GREEN coverage | SceneInteractionComponentTests | navigationGizmoOffersAllSixAxisActions passes against the concurrently implemented NavigationGizmo. NavigationGizmoTests projection/depth/preset cases also pass in the full run. Earlier AX-harness failures are not feature-red evidence. No claim of observed preimplementation behavioral red. |
| 1cxtu56y | RED | SceneInteractionComponentTests | selectingAQuadShowsItsDimensionsInsteadOfTheWholeScene fails: a selected 2×2×0 quad reports whole-scene depth rather than 2.00 × 2.00 × 0.00 m. The real GLB scene union is asserted as 2×2×1; standalone dimensions AX control passes. Clear-selection/material/group/name cases remain. |
| sygpfhz7 | RED (initial visibility) | SceneInteractionComponentTests | animatedFileOffersPlaybackControls fails: a loaded BoxAnimated fixture with duration > 0 exposes no Play control. staticFileDoesNotOfferPlaybackControls passes. Play/pause/scrub/speed behavior awaits bi329hbl; this is not full HUD coverage. |
| lusha0c3 | RED | SceneSelectionRoutingTests | repeatedMeshHitsCycleThroughParentsAndBack fails at Group and Root: repeated real canvas callbacks keep selecting the mesh. Different-hit/background controls pass. Parent/children menu cases remain. |
| g7bd2y5a | RED | SceneSelectionRoutingTests | selectingAUsedMaterialChangesRendererHighlightOptions fails: a material used by two nodes leaves render options identical to no selection. Unused-material and clear-selection controls pass. Exact highlighted-user set and rendered AABBs remain. |
| hc4no7yk | GREEN existing regression | OutlinerTreeTests | pathToReturnsAncestorsThenSelf and revealExpandsAncestorsWithoutCollapsingOthers pass. These tests existed in ongoing work; do not claim new red evidence or completed scroll/reveal UI coverage. |
| yo39dosw | GREEN existing regression | FrameSelectionTests | frameNodeMovesTargetToSubtreeCentreAndKeepsOrbit and frameSelectionNoopsWithoutSceneNodeAndClearsFileCamera pass against concurrent implementation. No preimplementation red was observed here; viewport corners/context menu/Fit cases remain. |
| hc7w6r13 | RED reference regression | PixelDiffMetalTests | All sample references pass. FeatureReferenceTests.everyFeatureMatchesItsKhronosReference fails for selection and all-overlays: the cyan selection AABB is absent in actual images (2.0691% differing pixels). Actual/expected/diff PNGs were inspected and archived under proof/reference-diffs. This comes from the captured concurrent source changes; no references were regenerated and no production fix was made by this testing task. |

## Defined but not executable yet

The following 16 leaves retain concrete contracts, but cannot honestly be called behavioral red without their APIs/prerequisites. No fake implementation, unconditional failing assertion, compiler error, skip, or weakened oracle substitutes for a behavioral test. No feature task is completed by this report.

- **0yc5sao4:** No adopt/shared-scene entry point or sceneGeneration exists yet. First introduce the agreed callable interface, then implement the defined buffer-identity/load-spy tests and observe compiling behavioral red before the adoption algorithm. No placeholder loader is added here.
- **115ut2u1:** Animated manifest evaluation and independently captured fixed-time Khronos images are absent. Depends on pose/morph/skin work. Existing rest-pose references pass; that is not animated-pose coverage. Do not generate new goldens from Metal.
- **63uvhpzt:** Optional polish has no selected-ID edge-compositing seam yet. Define the capture/edge-mask test against that seam when accepted; existing AABB tests are not silhouette tests.
- **advg8yaq:** The task is timeboxed and has not selected accepted additional modes; current RenderViewMode has no x-ray/clay/combined wireframe mode. Choose the subset first, then add the corresponding rendering assertions before its pipeline changes.
- **bi329hbl:** No playback state/clock-injection/clip-selection API exists. Depends on q9fppsgo. Timeline initial-visibility red is tracked on sygpfhz7, not passed off as playback timing coverage.
- **cm2j1flm:** OutlinerTree.Row has no guide flags yet. The pure guide contract is defined above; add the callable flag computation contract and exact row-array tests before its algorithm. Existing visibleRows tests pass but do not test guides.
- **huj04ed6:** Per-frame pose/joint-palette GPU seam does not exist; depends on z8bzuhwz. Rest-skin rendering is not animated GPU-skinning coverage. Use the defined independent CPU oracle once pose input is callable.
- **ifz67ezm:** AnimationSampler type/callable signature is absent. This is the first animation implementation seam, not a dependency on another feature. Establish its compileable input/output interface, then add the defined numeric assertions to red before sampling math. No fake sampler implementation or compiler error is counted as behavioral red.
- **lf9s93sq:** No selection-retarget/cursor-ray input or settings seam exists. Current camera tests cover established Khronos orbit math only. Introduce the explicit retarget/dolly interface and then the defined independent camera assertions before its behavior.
- **oebu83te:** gizmoHit/projected tagged segments API is absent and gizmo geometry is prerequisite work. The camera/light geometry tests are red, but do not exercise gizmo hit tolerance or precedence.
- **q9fppsgo:** No per-frame Pose input/draw-transform evaluation seam exists; depends on rc2v1tsr. Static draw matrices and passing rest references do not prove animation.
- **rc2v1tsr:** AnimationClip/Pose interfaces are absent; depends on ifz67ezm. The sampler/pose numeric contracts are defined, but not executable until those signatures are introduced.
- **swrmm3ku:** Optional exporter has no frame-source/encoder API. Keep it optional and introduce a callable export seam before the defined decode/frame-count/cancel tests; no Export sheet is left open.
- **vn4trm11:** Selection is still a single NodeID and the pick callback carries one index with no selection modifiers. A set/primary-selection command seam is needed for the toggle/aggregate-action contracts. Existing plain-click tests are not multiselect tests.
- **yel6vru3:** No hovered-node, idle-throttle or injected pick/clock seam exists; depends on picking. Define this callable contract before its production behavior, then run the deterministic cases above; no wall-clock sleep or fake hover implementation is added.
- **z8bzuhwz:** No per-frame morph-weight/delta-buffer input exists; depends on q9fppsgo. Passing rest references do not prove dynamic GPU morphing. Add the defined CPU-oracle comparisons when weight inputs are callable.
