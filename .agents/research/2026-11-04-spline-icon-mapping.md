# Spline icons → glTF Inspector

Where the icons exported to `~/Downloads/spline-icons/` (contact sheet: its `index.html`) fit in the
app. Each row shows the icon the app draws **today** (SF Symbol) next to the **Spline** one.
Source: two saved snapshots of Spline's editor (Blocks Flow), 4 Nov 2026.

## Before using any of them

- **They are Spline's artwork.** Use them as a reference, or get permission before bundling them.
- **The app's icon rule is "SF Symbols only".** `DSTypeIcon` and DESIGN.md ("System first") say
  icons track the system font, with no bundled artwork. Where SF Symbols has no glyph (normal map,
  cavity, torus, icosahedron…), draw our own as **custom SF Symbol templates** in the asset catalog
  (`Image("torus")`), so weight and tint still follow the system. No loose PNGs or SVGs.

## 1. Identifying primitives: yes, mostly

A glTF file has no "cube" field, but we can usually tell from what it does carry:

1. **Name.** Spline, Blender and most exporters keep the object name: this file has `Cube 4`,
   `Long Cube`, `Cylinder`, `Ellipse`, `Triangle`. Match whole words in the node and mesh name
   (`cube`, `box`, `sphere`, `cylinder`, `cone`, `torus`, `plane`…), ignoring suffixes like `.001` and ` 4`.
2. **Geometry.** Weld duplicate positions and test the shape (table below). The bounding box comes
   free from the `POSITION` accessor's `min`/`max` in the JSON. The shape tests need the vertex
   positions, so run them only on small meshes (under ~5 000 vertices) while the renderer loads the
   buffers, and hand the result to the outliner.
3. **Rule.** For a shape we can test (cube, sphere, cylinder…) the icon needs the geometry to agree.
   A name alone never wins, so a sculpt called `Cube.003` keeps the generic icon. For shapes we
   can't test (teapot, bunny, knot, text) the name alone decides. Anything else keeps today's cube.

| Primitive | Today | Spline | How to tell |
| --- | :-: | :-: | --- |
| Cube, box ("Long Cube") | <img src="assets/spline-icon-mapping/sf-cube.png" width="16" height="16" alt="cube"> | <img src="assets/spline-icon-mapping/spline-outliner-type-cube.png" width="16" height="16" alt="outliner-type-cube"> | 8 unique corner positions, all on the bounding box |
| Plane | <img src="assets/spline-icon-mapping/sf-cube.png" width="16" height="16" alt="cube"> | <img src="assets/spline-icon-mapping/spline-add-menu-plane.png" width="16" height="16" alt="add-menu-plane"> | 4 unique positions; one bounding-box side ≈ 0 |
| Sphere | <img src="assets/spline-icon-mapping/sf-cube.png" width="16" height="16" alt="cube"> | <img src="assets/spline-icon-mapping/spline-add-menu-sphere.png" width="16" height="16" alt="add-menu-sphere"> | every position the same distance from the centre (±1 %) |
| Cylinder | <img src="assets/spline-icon-mapping/sf-cube.png" width="16" height="16" alt="cube"> | <img src="assets/spline-icon-mapping/spline-outliner-type-cylinder.png" width="16" height="16" alt="outliner-type-cylinder"> | two cap heights along one axis; constant radius around it |
| Cone | <img src="assets/spline-icon-mapping/sf-cube.png" width="16" height="16" alt="cube"> | <img src="assets/spline-icon-mapping/spline-add-menu-cone.png" width="16" height="16" alt="add-menu-cone"> | radius falls linearly to one apex point |
| Pyramid | <img src="assets/spline-icon-mapping/sf-cube.png" width="16" height="16" alt="cube"> | <img src="assets/spline-icon-mapping/spline-add-menu-pyramid.png" width="16" height="16" alt="add-menu-pyramid"> | 5 unique positions |
| Icosahedron | <img src="assets/spline-icon-mapping/sf-cube.png" width="16" height="16" alt="cube"> | <img src="assets/spline-icon-mapping/spline-add-menu-icosahedron.png" width="16" height="16" alt="add-menu-icosahedron"> | 12 unique positions, all equidistant |
| Dodecahedron | <img src="assets/spline-icon-mapping/sf-cube.png" width="16" height="16" alt="cube"> | <img src="assets/spline-icon-mapping/spline-add-menu-dodecahedron.png" width="16" height="16" alt="add-menu-dodecahedron"> | 20 unique positions, all equidistant |
| Torus | <img src="assets/spline-icon-mapping/sf-cube.png" width="16" height="16" alt="cube"> | <img src="assets/spline-icon-mapping/spline-add-menu-torus.png" width="16" height="16" alt="add-menu-torus"> | every position the same distance from a ring |
| Torus knot, helix, lathe | <img src="assets/spline-icon-mapping/sf-cube.png" width="16" height="16" alt="cube"> | <img src="assets/spline-icon-mapping/spline-add-menu-torus-knot.png" width="16" height="16" alt="add-menu-torus-knot"> <img src="assets/spline-icon-mapping/spline-add-menu-helix.png" width="16" height="16" alt="add-menu-helix"> <img src="assets/spline-icon-mapping/spline-add-menu-lathe.png" width="16" height="16" alt="add-menu-lathe"> | name only |
| Teapot, bunny | <img src="assets/spline-icon-mapping/sf-cube.png" width="16" height="16" alt="cube"> | <img src="assets/spline-icon-mapping/spline-add-menu-teapot.png" width="16" height="16" alt="add-menu-teapot"> <img src="assets/spline-icon-mapping/spline-add-menu-bunny.png" width="16" height="16" alt="add-menu-bunny"> | name only |
| 2D shapes: rectangle, ellipse, triangle, pentagon, star | <img src="assets/spline-icon-mapping/sf-cube.png" width="16" height="16" alt="cube"> | <img src="assets/spline-icon-mapping/spline-outliner-type-shape-2d.png" width="16" height="16" alt="outliner-type-shape-2d"> <img src="assets/spline-icon-mapping/spline-outliner-type-ellipse.png" width="16" height="16" alt="outliner-type-ellipse"> <img src="assets/spline-icon-mapping/spline-outliner-type-triangle.png" width="16" height="16" alt="outliner-type-triangle"> <img src="assets/spline-icon-mapping/spline-add-menu-pentagon.png" width="16" height="16" alt="add-menu-pentagon"> <img src="assets/spline-icon-mapping/spline-add-menu-star.png" width="16" height="16" alt="add-menu-star"> | name; geometry check: one thin bounding-box side (flat or a shallow extrusion) |
| Text | <img src="assets/spline-icon-mapping/sf-cube.png" width="16" height="16" alt="cube"> | <img src="assets/spline-icon-mapping/spline-toolbar-create-text-object.png" width="16" height="16" alt="toolbar-create-text-object"> | name only |
| Line / path mesh (`mode` 1–3) | <img src="assets/spline-icon-mapping/sf-cube.png" width="16" height="16" alt="cube"> | <img src="assets/spline-icon-mapping/spline-outliner-type-path.png" width="16" height="16" alt="outliner-type-path"> | primitive `mode`, a fact in the JSON |
| Point cloud (`mode` 0) | <img src="assets/spline-icon-mapping/sf-cube.png" width="16" height="16" alt="cube"> | <img src="assets/spline-icon-mapping/spline-add-menu-particle-emitter.png" width="16" height="16" alt="add-menu-particle-emitter"> | primitive `mode` |
| Any other mesh | <img src="assets/spline-icon-mapping/sf-cube.png" width="16" height="16" alt="cube"> | <img src="assets/spline-icon-mapping/spline-outliner-type-cube.png" width="16" height="16" alt="outliner-type-cube"> | fallback: today's generic cube |

Spline's 2D shapes export as thin extruded meshes, so they usually need the name. A primitive's
`mode` (points / lines / triangles) is plain JSON, so line and point meshes are the easiest win.

## 2. Groups: drop the folder

Today an empty node with children shows <img src="assets/spline-icon-mapping/sf-folder.png" width="16" height="16" alt="folder"> `folder` in the glyph slot, and swaps to
<img src="assets/spline-icon-mapping/sf-chevron.right.png" width="16" height="16" alt="chevron.right"> on hover to fold.

Spline actually keeps both: a boxed chevron column on the left, plus a type icon. A plain group
(its "Marker Cap" row) gets <img src="assets/spline-icon-mapping/spline-outliner-type-group.png" width="16" height="16" alt="outliner-type-group">, and a boolean (Bridge) gets <img src="assets/spline-icon-mapping/spline-outliner-type-boolean-subtract.png" width="16" height="16" alt="outliner-type-boolean-subtract">.

**Recommendation:** for an **empty group**, put the chevron in the glyph slot all the time
(<img src="assets/spline-icon-mapping/sf-chevron.right.png" width="16" height="16" alt="chevron.right"> folded / <img src="assets/spline-icon-mapping/sf-chevron.down.png" width="16" height="16" alt="chevron.down"> open) and drop the folder, as you suggest. The chevron already says
"holds things", and a separate icon would be noise. A **mesh, camera or light with children** keeps
its type icon and swaps to the chevron on hover as today, because its type is the more useful fact.
This is a change to `DSOutlineRow` / `DSTypeIcon` only, plus keyboard and VoiceOver labels.

## 3. Outliner: other object types

| Row | Today | Spline | Notes |
| --- | :-: | :-: | --- |
| Camera | <img src="assets/spline-icon-mapping/sf-video.png" width="16" height="16" alt="video"> | <img src="assets/spline-icon-mapping/spline-outliner-type-camera.png" width="16" height="16" alt="outliner-type-camera"> | Same glyph. Keep SF `video`. |
| Directional light | <img src="assets/spline-icon-mapping/sf-sun.max.png" width="16" height="16" alt="sun.max"> | <img src="assets/spline-icon-mapping/spline-outliner-type-directional-light.png" width="16" height="16" alt="outliner-type-directional-light"> | `Light.type == "directional"`. Data already there. |
| Point light | <img src="assets/spline-icon-mapping/sf-sun.max.png" width="16" height="16" alt="sun.max"> | <img src="assets/spline-icon-mapping/spline-add-menu-point-light.png" width="16" height="16" alt="add-menu-point-light"> | `Light.type == "point"`; SF `lightbulb` <img src="assets/spline-icon-mapping/sf-lightbulb.png" width="16" height="16" alt="lightbulb"> |
| Spot light | <img src="assets/spline-icon-mapping/sf-sun.max.png" width="16" height="16" alt="sun.max"> | <img src="assets/spline-icon-mapping/spline-add-menu-spot-light.png" width="16" height="16" alt="add-menu-spot-light"> | `Light.type == "spot"`; SF `lamp.desk` <img src="assets/spline-icon-mapping/sf-lamp.desk.png" width="16" height="16" alt="lamp.desk"> |
| Mesh instance (2+ nodes share a mesh) | <img src="assets/spline-icon-mapping/sf-cube.png" width="16" height="16" alt="cube"> | <img src="assets/spline-icon-mapping/spline-outliner-type-component.png" width="16" height="16" alt="outliner-type-component"> | New: count shared `meshIndex`. Shows reused geometry. |
| Animation | <img src="assets/spline-icon-mapping/sf-waveform.path.png" width="16" height="16" alt="waveform.path"> | <img src="assets/spline-icon-mapping/spline-mode-timeline-stopwatch.png" width="16" height="16" alt="mode-timeline-stopwatch"> | Stopwatch reads as time; SF `stopwatch` <img src="assets/spline-icon-mapping/sf-stopwatch.png" width="16" height="16" alt="stopwatch"> |
| Scene (default `scene`) | <img src="assets/spline-icon-mapping/sf-square.stack.3d.up.png" width="16" height="16" alt="square.stack.3d.up"> | <img src="assets/spline-icon-mapping/spline-scene-home.png" width="16" height="16" alt="scene-home"> | Spline marks the start scene with a house; SF `house` <img src="assets/spline-icon-mapping/sf-house.png" width="16" height="16" alt="house"> |
| Empty leaf node | <img src="assets/spline-icon-mapping/sf-circle.dotted.png" width="16" height="16" alt="circle.dotted"> | – | No Spline equivalent; keep. |
| Material | <img src="assets/spline-icon-mapping/sf-circle.lefthalf.filled.png" width="16" height="16" alt="circle.lefthalf.filled"> | – | Keep; see Materials for swatches. |
| Skin / morph | <img src="assets/spline-icon-mapping/sf-point.3.connected.trianglepath.dotted.png" width="16" height="16" alt="point.3.connected.trianglepath.dotted"> <img src="assets/spline-icon-mapping/sf-slider.horizontal.3.png" width="16" height="16" alt="slider.horizontal.3"> | – | No Spline equivalent; keep. |
| Boolean (Spline only) | – | <img src="assets/spline-icon-mapping/spline-outliner-type-boolean-intersect.png" width="16" height="16" alt="outliner-type-boolean-intersect"> <img src="assets/spline-icon-mapping/spline-outliner-type-boolean-subtract.png" width="16" height="16" alt="outliner-type-boolean-subtract"> | No glTF equivalent. |

## 4. Row controls, sidebar, toolbar

| Control | Today | Spline | Notes |
| --- | :-: | :-: | --- |
| Visibility toggle | <img src="assets/spline-icon-mapping/sf-eye.png" width="16" height="16" alt="eye"> <img src="assets/spline-icon-mapping/sf-eye.slash.png" width="16" height="16" alt="eye.slash"> | <img src="assets/spline-icon-mapping/spline-outliner-visibility.png" width="16" height="16" alt="outliner-visibility"> | Spline's half-open eye is lighter; keep `eye` for familiarity. |
| Fold chevron | <img src="assets/spline-icon-mapping/sf-chevron.right.png" width="16" height="16" alt="chevron.right"> | <img src="assets/spline-icon-mapping/spline-outliner-expand.png" width="16" height="16" alt="outliner-expand"> | Same; keep the system chevron. |
| Lock | – | <img src="assets/spline-icon-mapping/spline-outliner-lock-open.png" width="16" height="16" alt="outliner-lock-open"> <img src="assets/spline-icon-mapping/spline-outliner-lock-closed.png" width="16" height="16" alt="outliner-lock-closed"> | Not needed: the viewer is read-only. |
| Sidebar toggle (Cmd-B) | <img src="assets/spline-icon-mapping/sf-sidebar.left.png" width="16" height="16" alt="sidebar.left"> | <img src="assets/spline-icon-mapping/spline-sidebar-toggle.png" width="16" height="16" alt="sidebar-toggle"> | Same glyph. |
| Outliner search | <img src="assets/spline-icon-mapping/sf-magnifyingglass.png" width="16" height="16" alt="magnifyingglass"> | <img src="assets/spline-icon-mapping/spline-search.png" width="16" height="16" alt="search"> | Same glyph. |
| Outliner filter by type | <img src="assets/spline-icon-mapping/sf-line.3.horizontal.decrease.png" width="16" height="16" alt="line.3.horizontal.decrease"> | <img src="assets/spline-icon-mapping/spline-filter-by-type.png" width="16" height="16" alt="filter-by-type"> | If a type filter ships. |
| Perspective / orthographic | <img src="assets/spline-icon-mapping/sf-perspective.png" width="16" height="16" alt="perspective"> | <img src="assets/spline-icon-mapping/spline-camera-perspective.png" width="16" height="16" alt="camera-perspective"> | Spline's box reads as "3D view" more plainly. |
| Performance readout | – | <img src="assets/spline-icon-mapping/spline-performance-monitor.png" width="16" height="16" alt="performance-monitor"> | Only if a stats overlay ships; SF `waveform.path.ecg` <img src="assets/spline-icon-mapping/sf-waveform.path.ecg.png" width="16" height="16" alt="waveform.path.ecg"> |

## 5. Materials

Every view-mode channel uses <img src="assets/spline-icon-mapping/sf-cube.png" width="16" height="16" alt="cube"> today, and texture-slot rows have no icon. Spline's material
layer icons fit best here: one `TextureSlot.Kind` / `RenderViewMode.Channel` → icon table can serve
both the `MaterialSection` map rows and the View Mode menu.

| Slot / channel | Today | Spline | Why |
| --- | :-: | :-: | --- |
| Base colour | <img src="assets/spline-icon-mapping/sf-cube.png" width="16" height="16" alt="cube"> | <img src="assets/spline-icon-mapping/spline-material-layer-image.png" width="16" height="16" alt="material-layer-image"> | Real `thumbnailPNG` when there is one, this when not. |
| Normal | <img src="assets/spline-icon-mapping/sf-cube.png" width="16" height="16" alt="cube"> | <img src="assets/spline-icon-mapping/spline-material-layer-normal.png" width="16" height="16" alt="material-layer-normal"> | The purple–blue normal sphere is universal. |
| Occlusion | <img src="assets/spline-icon-mapping/sf-cube.png" width="16" height="16" alt="cube"> | <img src="assets/spline-icon-mapping/spline-material-layer-cavity.png" width="16" height="16" alt="material-layer-cavity"> | Cavity = crevice darkening = AO. |
| Metallic / roughness | <img src="assets/spline-icon-mapping/sf-cube.png" width="16" height="16" alt="cube"> | <img src="assets/spline-icon-mapping/spline-material-layer-matcap.png" width="16" height="16" alt="material-layer-matcap"> | Shaded sphere = surface response. |
| Emissive | <img src="assets/spline-icon-mapping/sf-cube.png" width="16" height="16" alt="cube"> | <img src="assets/spline-icon-mapping/spline-material-layer-fresnel.png" width="16" height="16" alt="material-layer-fresnel"> | Glowing ring. |
| Specular, spec-gloss workflow | <img src="assets/spline-icon-mapping/sf-cube.png" width="16" height="16" alt="cube"> | <img src="assets/spline-icon-mapping/spline-material-layer-reflection.png" width="16" height="16" alt="material-layer-reflection"> |  |
| Clearcoat (+ roughness, normal) | <img src="assets/spline-icon-mapping/sf-cube.png" width="16" height="16" alt="cube"> | <img src="assets/spline-icon-mapping/spline-material-layer-toon.png" width="16" height="16" alt="material-layer-toon"> | Glossy shell; add a modifier for roughness / normal. |
| Alpha, mask / blend | <img src="assets/spline-icon-mapping/sf-cube.png" width="16" height="16" alt="cube"> | <img src="assets/spline-icon-mapping/spline-checkerboard-pattern.png" width="16" height="16" alt="checkerboard-pattern"> | Checkerboard = transparency. |
| UVs | <img src="assets/spline-icon-mapping/sf-cube.png" width="16" height="16" alt="cube"> | <img src="assets/spline-icon-mapping/spline-material-layer-pattern.png" width="16" height="16" alt="material-layer-pattern"> | Tiling hints at UV layout. |
| Vertex colours (`hasVertexColors`) | – | <img src="assets/spline-icon-mapping/spline-material-layer-vertex-color.png" width="16" height="16" alt="material-layer-vertex-color"> | Chip in Geometry; flag already exists. |
| Unlit workflow | – | <img src="assets/spline-icon-mapping/spline-material-layer-gradient.png" width="16" height="16" alt="material-layer-gradient"> | Flat shading. |
| Tangents | <img src="assets/spline-icon-mapping/sf-cube.png" width="16" height="16" alt="cube"> | – | No Spline equivalent. |
| Wireframe view mode | <img src="assets/spline-icon-mapping/sf-grid.png" width="16" height="16" alt="grid"> | – | Keep. |
| Material header swatch | <img src="assets/spline-icon-mapping/sf-circle.lefthalf.filled.png" width="16" height="16" alt="circle.lefthalf.filled"> | <img src="assets/spline-icon-mapping/spline-material-preview.png" width="16" height="16" alt="material-preview"> | A sphere in `baseColorFactor`, drawn in SwiftUI. |

## 6. Not useful in a viewer

Editing tools with nothing to drive them: toolbar pen / comment / design cursor, particles, hair,
shape blend, decal, input, templates, new scene, add modifier, material unlink / palette, pin
preview, dialog close, number-field and lock baubles, `radio-boolean-*`, drag-and-drop event,
AI texture <img src="assets/spline-icon-mapping/spline-material-layer-ai-texture.png" width="16" height="16" alt="material-layer-ai-texture"> and its badge <img src="assets/spline-icon-mapping/spline-badge-ai-lightning.png" width="16" height="16" alt="badge-ai-lightning">, resize cursor, favicon.

## Icon check (4 Nov)

Every inline SVG in both snapshots now has a file. Fixes in this pass:
`outliner-type-boolean` → `outliner-type-boolean-intersect` ("halfmoon"),
`outliner-type-boolean-2` → `outliner-type-boolean-subtract` ("Bridge"). I also added two
glyphs the first pass missed: `material-layer-ai-texture` and `badge-ai-lightning`. Some files share a glyph under
two names because Spline reuses it, e.g. `outliner-type-group` = `add-menu-group` and
`outliner-type-cube` = `toolbar-create-3d-object`.

## Suggested order

1. **Groups without the folder** (section 2): small, and it's the change you asked about.
2. **Light subtypes**: directional / point / spot from `Light.type`.
3. **Line / point meshes** from primitive `mode`, then **name + geometry primitives**.
4. **Material and channel glyphs**: one shared table; draw custom symbols for normal, cavity and vertex colour.
5. **Mesh instances** from shared `meshIndex`.
