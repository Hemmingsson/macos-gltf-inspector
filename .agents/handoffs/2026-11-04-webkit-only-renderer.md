# Handoff: WebKit-only renderer (RealityKit removed)

- **Branch / worktree:** `claude/remove-metal-webkit-only-a816c1` at
  `.claude/worktrees/remove-metal-webkit-only-a816c1`, based on `8507c3d`.
- **State:** all work is **uncommitted** (≈354 files, +1.1k / −24.6k lines). `main` has since
  moved to `69edd88`; sync before merging.
- **Installed:** this branch's Debug build is in `/Applications/glTF Inspector.app`, and its
  Quick Look + thumbnail extensions are the registered ones (`pluginkit -mAvvv`). Running
  `./scripts/build.sh` on main replaces it with main's (two-renderer) build.

## Goal

Make the repo read as if WebKit had always been the only renderer. That means no RealityKit
("Metal"), no renderer setting, no "default/primary renderer", and no feature gating between
renderers. Every surface (window, Quick Look, Finder thumbnail) draws through one `WKWebView`
page running the vendored Khronos glTF Sample Renderer (`RendererWebKit/web-renderer/`).

## What changed

**Removed**
- The `RendererRealityKit` target, the GLTFKit2 and DracoSwift packages, `GLTFInspector/RealityKit/`,
  `GLTFInspectorTests/RealityKit/`, `TestModels/References/realitykit/`, and the RK Quick Look and
  thumbnail files.
- `RendererKind`, `RendererRouter`, the `settings.preview.renderer` key, the Settings renderer
  picker, the `-GLTFRenderer` launch argument, `RendererFeature`, `RendererAvailability`,
  `WebPreviewCanvas.features`, and the View-menu toggle availability.
- **Chrome the page can't drive:**
  - animation: playback bar and play button, `ClipPlaybackController` and its mocks;
  - morph weight sliders;
  - hide/solo (the outliner eye);
  - View menu: Double-Sided and Show Skeleton;
  - Lighting popover: the file-lights picker;
  - Settings: "Use environment map" and "Add your own…" (custom HDR);
  - Sidebar: the convert-problems and pipeline-report sections;
  - `AppLook` / `look.json`.
- **Dead code:** Quick Look overlay facts in `PreviewStats`, skeleton-only document fields,
  RK-only `ModelBounds` outlier rule, `CachedQuickLookThumbnail` (already unused),
  `GLTFInspectorError`, `scripts/proof.sh`, and RK research notes in `.agents/research/`.

**Restructured**
- `PreviewExtension/PreviewViewController.swift` and `ThumbnailExtension/ThumbnailProvider.swift`
  contain the WebKit path directly, with no router.
- `GLTFInspector/DocumentWindow.swift` (formerly `WebKit/WebDocumentWindow`) is the window root;
  the `WebKit/` subfolders are flattened.
- `Availability` (PreviewUI) is a concrete struct (view-mode channels only); the
  `Capabilities` generic is gone.
- The environment choice is the App Group key `settings.preview.environmentCatalog`, read by
  `AppGroupSettings.rendererLook()`. `KhronosEnvironments` lives in GLTFCore.
- Pixel goldens live directly in `TestModels/References/` (manifest v3, single tolerance);
  `regenerate-pixel-references.sh` takes no renderer argument.
- Docs rewritten: `AGENTS.md`, `README.md`, `DESIGN.md`, `docs/pipeline-web-renderer.md`
  (absorbed the old WebKit decision record), `.vscode`, `.agents/agents`, skills.

**Bugs fixed along the way**
1. **Reload loop on a rejected file.** It already existed at `8507c3d`: 136 "viewport failed" in 8 s. A
   failed load is now terminal for that URL (`WebCanvasController.reload`), covered by
   `corruptFileEndsInFailedNotASpinner`.
2. **Outliner camera.** `.camera` (and `.light`) outliner IDs are *node* indices. The sidebar now
   stores `selectedCameraNodeIndex` and passes it straight to the page. The inspector resolves
   camera and light rows through the node, and a scene switch clears the camera. The test drives
   the ID through the real outliner (`HostSidebarModelTests.fileCameraReachesTheLookAsItsNodeIndex`).
3. **`dev.sh install` treated `.claude/worktrees/*` as main** and copied to `/Applications`.
   `scripts/lib/dev-env.sh` now compares `git rev-parse --git-dir` with `--git-common-dir`.

## Verification done

- `./scripts/dev.sh test`: **150 tests, 37 suites, all pass**, including all 21 pixel-diff
  samples. The Khronos samples were copied from the main checkout's gitignored
  `TestModels/Khronos samples/`.
- `DesignCatalog` builds; `GLTFInspectorUITests` passes `build-for-testing`. **The UI tests were
  not run** (they steal focus).
- **Real window** (`dev.sh run` + direct launches):
  - BoxAnimated, cameras, lights, multiScene: one `open start` / `open ready` each, with
    `viewport ready` and no `Modifying state` warnings.
  - truncated.glb: fails once.
  - unresolved-mesh.gltf: fails, gets one page restart, then stops.
- An independent code review ran; findings 1–3 above came out of it and are fixed.
- **Not verified:** a live Quick Look panel or Finder thumbnail render of the installed app
  (`qlmanage -t` hangs headless). Check by pressing Space on a `.glb` in Finder.

## How the viewer changes what you see

The page **never modifies the model's geometry, materials or transforms**. Everything below is
camera, lighting, or line overlays drawn after the Khronos frame (`viewer.html` `drawOverlays`).

| Control | What it actually does | Window default | Quick Look | Thumbnail |
| --- | --- | --- | --- | --- |
| **Center** (`centered`) | Camera only: it aims at the scene's bounds centre. Off keeps the authored origin in frame (`includeOriginInFraming`) and draws an origin gizmo. The model is never moved. | on (`settings.preview.center`) | on | on |
| **Fit / framing** | Projected-AABB fit with near-face depth and 1.02 padding (`sharedFitDistance`, same rule as `RenderCamera.fitDistance`), front view. Runs on open, scene switch, centre toggle and Fit/Reset. | on open | on open | on open |
| **Camera presets** | Front / back / left / right / top / bottom orbit angles at the shared fit distance (`CameraPreset.webOrbitAngles`). | — | — | — |
| **File camera** | Outliner camera row → page `cameraNodeIndex`; the page views through that node's camera. | none | none | none |
| **Field of view** | User camera `yfov`. | 35° (`RenderCamera.defaultFieldOfViewDegrees`) | 45° (`Look()` default) | 45° |
| **Projection** | Orthographic magnification derived from the camera distance, restated after every fit. | perspective (`settings.preview.projection`) | perspective | perspective |
| **Auto-rotate** | Orbits the *camera* 1.2 units/frame; the model does not turn. | on (`settings.preview.autoRotate`) | off | off |
| **Floor** | Grey polar grid of *lines*, not a surface: 4 rings, 8 radials, diameter 2.7 × max(X, Z) extent, just under the model's min Y. No shadow or reflection. | on (`settings.preview.showFloor`) | on (`stored(showsFloor: true)`) | off |
| **Background** | Page background behind a transparent canvas; the HDR is not shown as background (`renderEnvironmentMap = false`). | `window` (`settings.preview.background`) | clear (host window shows) | clear |
| **Environment (IBL)** | Bundled Khronos HDR lights the model. The first frame uses Khronos key+fill lights, then the IBL lands a frame or two later. | Studio Neutral (`settings.preview.environmentCatalog`) | stored setting | stored setting |
| **Environment rotation** | `environmentRotation = 90 + yaw` (yaw 0 = Khronos default view). | 0 | 0 | 0 |
| **Exposure / intensity** | `exposure = 2^EV`, `iblIntensity` 1:1. | 0 EV / 1 | 0 / 1 | 0 / 1 |
| **Tone mapping** | Khronos `toneMap` by name. | PBR Neutral (`settings.preview.toneMapping`) | stored | stored |
| **File lights** | `KHR_lights_punctual` always drawn as authored, alongside the IBL; there is no toggle. | always | always | always |
| **View mode** | Shaded, wireframe (GPU line mode or cached CPU lines), or Khronos debug channel (`debugOutput`). Only channels the file has data for are offered. | shaded | shaded | shaded |
| **Selection** | Blue AABB line box around the selected node's subtree. | none | — | — |
| **Material variant** | `KHR_materials_variants` index; nil = file default. | file default | file default | file default |
| **Scene** | Which glTF scene draws; 0 = the file's default scene. | file default | file default | file default |
| **Pointer input** | Drag orbits, shift/middle-drag pans, scroll is an infinite dolly (no clamp). | live | live | — |
| **Animations / morphs / skins** | The page draws the bind/rest pose; nothing plays or poses. The inspector still lists them. | — | — | — |

**Did this branch change what users see?**
- **One-time resets:**
  - A stored environment choice falls back to Studio Neutral once, because `look.json` is no
    longer read.
  - Finder posters re-render once, because the poster key dropped the renderer and the
    env-map flag.
- **Behavior changes:**
  - **Dimensions readout:** dimensions and the authored origin now include outliers such as a huge
    ground plane, because the RK-only outlier rule is gone. This matches what the page frames.
  - **Lighting popover:** the File Lights picker is gone.
  - **Settings:** "Use environment map" and "Add your own…" are gone. Neither ever affected
    the WebKit page.
  - **Outliner cameras:** a camera row now actually switches the view. Before, it did nothing
    on the page.
- **Unchanged:** the WebKit window, Quick Look and thumbnail renders look the same. All pixel
  goldens pass unchanged.

## Known issues / not done

- **Skin IDs are ambiguous.** `.skin` IDs mean a node index in the scene tree but a skin index in
  the Skins section, so a skinned node's inspector detail can be wrong. This predates the branch.
- **DESIGN.md asks for "viewer limits"** in the inspector. Nothing shows them now; page
  `warning` events are only logged (`WebRendererHost`).
- **Leftover data in the App Group:** old `look.json`, `ibl/`, posters and the removed keys. It
  is harmless and nothing prunes it.
- **Quick Look FOV differs:** it uses 45°, the window 35°. This predates the branch; worth
  aligning if the two should match.

## Next steps

1. Review the diff (`git diff HEAD` in the worktree), then commit on the branch.
2. Sync with `main` (`69edd88`) and resolve conflicts; main still has RealityKit, so expect
   conflicts in deleted RK files and docs.
3. Run `./scripts/dev.sh uitest` once (it steals focus).
4. Check Quick Look and Finder thumbnails by hand on a few `.glb` files.
5. After merging, `./scripts/build.sh` on main installs the merged app to `/Applications`.
