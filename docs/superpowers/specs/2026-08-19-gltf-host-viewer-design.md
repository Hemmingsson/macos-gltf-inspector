# glTF host viewer (RealityKit)

Date: 2026-08-19  
Status: draft for user review  
Repo: glb-preview (macOS 15+ Quick Look + Finder thumbnails + host app)

## Goal

Turn the **host app** into a session-only glTF inspector/viewer in the spirit of [Khronos glTF Sample Viewer](https://github.com/KhronosGroup/glTF-Sample-Viewer). RealityKit is the native renderer only. Outliner, inspector copy, units, and control names follow glTF / Sample Viewer, not RealityKit type names.

Quick Look and Finder thumbnails stay chrome-less. They must use the same **default look** as the host on open, so Spacebar / icons match the document window until the user moves a host-only control.

## Product decisions

| Decision | Choice |
|---|---|
| Where the UI lives | Host app only |
| Persistence | Session only. Closing the window discards Display, debug, hide/solo, HDR adds, scene/camera/clip/variant picks |
| Outliner | glTF graph only (scenes, nodes, meshes, cameras, lights). Injected studio IBL and Fit camera are not list rows |
| Selection | Outliner first. Viewport click is designed (`CollisionComponent` + raycast → same `nodeId`) and implemented later |
| First ship surface | Full Sample Viewer Display controls + core debug + artist extras below |
| Architecture | Approach 1: glTF session document + `nodeId → Entity` map + `ViewerSession.apply` |

## Non-goals (this ship)

- Writing or exporting glTF
- Per-file remembered prefs
- Display chrome in Quick Look or thumbnails
- UV checker, matcap, vertex normals, Specular F0, skeleton overlay, morph sliders
- Extension kill-switches (transmission, sheen, …)
- Grid / ground shadow / screenshot export
- Fake “Khronos PBR Neutral” that is only RealityKit’s default tone map
- Scene switch or Display in Finder

## Default look (host open = QL = thumbnail)

One `DefaultLook.apply` used by host on load, `GLBPreviewView` (Quick Look), and `RealityRenderer` thumbnails:

1. Convert the **default scene** (`asset.defaultScene` / glTF `scene`).
2. Studio IBL always attached. `intensityExponent` is **0** if the file has no punctual lights, **−2** if it does (current scenery rule).
3. File punctual lights enabled when present.
4. Fit camera (file cameras exist but are inactive until the host picks one).
5. Backdrop is the current clear / white / dark cycle — **not** a skybox.
6. Debug mode none. Exposure gain 1. Environment Map off. Blur off. Tone map is RealityKit’s built-in (no Neutral post-process).
7. If `KHR_materials_variants` exists, bind the file’s default / recommended variant so QL and thumbs match the host.
8. Thumbnails: `includeAnimations: false`. QL: first usable clip / existing scenery playback. No inspector.

Host Display sliders never change this path.

## Document model

Load remains prepare → GLTFKit2 → `GLBRealityKitConvert` → `Entity`. `GLTFAsset` is not kept for UI.

At convert time, snapshot value types (usable from the host):

- **Scenes** — name, root node ids, all entries in `scenes[]`.
- **Nodes** — name, children, optional mesh / camera / light, file TRS.
- **Meshes** — name, primitive count, triangle/vertex counts, material ids, world AABB after convert.
- **Materials** — glTF name, pbr factors, emissive, alpha mode, which textures exist.
- **Lights / cameras** — `KHR_lights_punctual` and glTF camera fields (not RK property names).
- **Animations** — name, duration (usable clips only, duration > 0).
- **Variants** — names + primitive → material remaps, or empty.
- **`nodeId → Entity`** stamped while each `nodeEntity` is created.

Multi-scene: host lists every scene. Default scene converts immediately (same as QL). Other scenes convert **on first select**, then stay cached for that window. Switch scene: show that root, hide others, clear selection, rebuild the layer list, Fit that scene’s bounds. `ViewerSession` Display/debug/HDR stays.

## Host chrome

Native **liquid glass** on macOS 26 (`glass` / sidebar materials, system `Toggle`, `Slider`, `Picker`, `ColorPicker`, `Menu`, `Button`). macOS 15: same layout, current non-glass fallback.

Three panes: left file | center `RealityView` | right view.

### Left — the file

**Model**

- Stats: existing `GLBPreviewStats`.
- Scene selector (v1, all scenes).
- Camera selector: Fit + file cameras (existing scenery switch: exactly one camera component active).
- Animations: play / pause / seek, per-clip enable. Selecting a clip shows name + duration in the right detail card.
- Variant picker: **only if** the file has `KHR_materials_variants`.

**Layer list** — nodes of the active scene. Eye (hide) and solo. Solo hides other **roots in the active scene**. “Show all” clears hide/solo.

### Right — the view

**Background** (first)

- Environment Map (default off) → `RealityView` skybox of the active HDR.
- Blur (default off) → blur **skybox only** (rougher prefilter / higher mip). IBL lighting stays sharp.
- Background Color — used when Environment Map is off.
- Environment Rotation — `+Z` / `−X` / `−Z` / `+X`. Rotates IBL entity and skybox, not the model.
- Active Environment — Studio + HDRs added this session.
- + Add New HDR — file picker / drop, session only.

**Lighting**

- Image Based — default **on** (Studio). Off removes IBL receivers. Uses Active Environment.
- Punctual Lighting — default on; off disables converted light components. No fake key light.
- IBL Intensity — log **0.01 … 10000**, default **1**. Maps onto `intensityExponent` so 1 equals DefaultLook’s 0 or −2.
- Exposure — log **0 … 64**, default **1** (photographic EV, not a light). Framebuffer gain.
- Tone Map — RealityKit, Khronos PBR Neutral, ACES Hill + exposure boost, ACES Narkowicz, ACES Hill, None. **Default on open is RealityKit** so the window matches QL/thumbs. Neutral is a host session choice, not DefaultLook.

**Debug** — None, Base Color, Roughness, Metalness, Normals, Emission, Wireframe.

**Detail card** (when something is selected; Lighting/Background stay)

- Node: name, read-only TRS, child count.
- Mesh: material card + per-mesh tris/verts + world AABB in meters.
- Camera / light: glTF fields, read-only.
- Animation clip: name, duration.

Nothing selected: no detail card. Stats stay on the left.

**Frame selected** — `F` and a button. Selection bounds via existing fit math. Nothing selected → Fit active scene.

## Exposure vs IBL intensity

These are different Sample Viewer controls.

- **IBL intensity** scales the environment *as light* (`ImageBasedLightComponent`).
- **Exposure** is photographic EV on the rendered HDR into the tone mapper ([Sample Viewer EV behavior](https://github.com/KhronosGroup/glTF-Sample-Viewer/issues/317), [Renderer API](https://github.com/KhronosGroup/glTF-Sample-Renderer/blob/HEAD/API.md)).

RealityKit has no camera-exposure API. Exposure and Neutral/ACES/None are a Metal `PostProcessEffect` using the published Khronos curves — not a relabel of IBL. **macOS 26+.** On 15, Exposure is visible and disabled; Tone Map is locked to RealityKit. QL/thumbs never use this post-process.

## Apply pipeline

`ViewerSession` (host only) holds Display, debug, selection, hide/solo, scene, camera, clips, variant, HDR list. `apply(to:)` mutates mapped entities only:

| Session field | RealityKit |
|---|---|
| Image Based | attach / detach `ImageBasedLightReceiverComponent` |
| IBL intensity / HDR / rotation | `ImageBasedLightComponent` + entity rotation |
| Punctual | light component `isEnabled` |
| Environment Map / blur / color | `content.environment` + backdrop |
| Debug channels | `ModelDebugOptionsComponent` (`.baseColor`, `.metallic`, `.roughness`, `.normal`, `.emissive`) |
| Wireframe | `triangleFillMode = .lines` on a **copy** of materials; leaving the mode restores cached originals |
| Hide / solo | `entity.isEnabled` |
| Variant | `ModelComponent.materials` from convert-time variant table |

If a `ModelDebugOptionsComponent` mode is blank on our `PhysicallyBasedMaterial` meshes, that mode falls back to an unlit swap from cached textures. No third renderer.

Viewport picking is specified (collision + `InputTargetComponent` + raycast → `nodeId`) and scheduled after the list-driven ship.

## Errors

- Convert failure → existing “Failed to load model.”
- Lazy scene convert failure → keep current scene; one-line inspector error.
- HDR decode failure → keep previous environment; one-line inspector error.
- Missing variant table → hide picker; keep default materials.
- Empty cameras / clips / lights → omit empty controls; do not invent lights.

## Code shape

- **`Shared/`** — convert-time IDs, variant table, mesh/material snapshot, `DefaultLook` (QL + thumbs + host open). No glass inspector.
- **`GLBPreview/`** — `NavigationSplitView` (or equivalent), outliner, inspector, `ViewerSession`, post-process tone map (26+).
- **`PreviewExtension` / `ThumbnailExtension`** — `LoadedModel` + `DefaultLook` only. Must not import `ViewerSession`.

## Tests

Proof is `xcodebuild` + `qlmanage`, not a browser.

- Two-scene synthetic GLB: document lists both; default entity is the default scene; host can switch after lazy convert.
- Node / light / camera ids resolve to entities.
- DefaultLook: exponent 0 vs −2; thumbnail lighting is studio HDR; no skybox; no debug component.
- IBL off removes receivers; punctual off disables lights; hide sets `isEnabled`.
- Variants: two-variant synthetic → remap materials; files without the extension have no picker.
- Debug: apply roughness then none restores materials.
- Extension targets compile without `ViewerSession`.

## RealityKit honesty (2026)

Native: IBL, punctual, skybox, HDR load, `ModelDebugOptionsComponent` channels, `triangleFillMode` wireframe, collision picking, `PostProcessEffect` (macOS 26).

Not native: Khronos tone maps and camera EV (we implement in post-process). Sample Viewer background blur (approximate with skybox mips only). `EXT_lights_image_based` (already logged, studio IBL remains).
