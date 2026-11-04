# Navigation gizmo: Spline and open-source references

**Question:** how does Spline's corner view gizmo work, how do open-source editors build the
same widget, and what should `GLTFInspector/Canvas/NavigationGizmo.swift` do better?

Sources: Spline editor watched live in the browser on a public file (behaviour only, no code
read). Source read for Blender (`view3d_gizmo_navigate_type.cc`, GPL-2.0+, so ideas only, no
code), Godot (`ViewportRotationControl`, MIT), three.js `ViewHelper.js` (MIT),
Fennec-hub/three-viewport-gizmo (MIT) and ImGuizmo `ViewManipulate` (MIT).
transform-gizmo and im3d only have transform manipulators, with no view widget. Values marked
*(unverified)* were not confirmed in source.

## What Spline does

- **Build.** It is a React `ViewCube` component. It draws on its own 78 pt canvas (2× DPR)
  inside an 80×80 white card with a 12 pt corner radius and the shadow
  `0 4 12 rgba(0,0,0,.075)`. The editor itself is three.js r185 on WebGPU.
- **Controls above the card.** Two 38×32 chips:
  - A cube button that toggles orthographic and perspective. Its label is "Switch to
    perspective camera" or "Switch to orthographic camera".
  - A `›` button that collapses the whole control to a single `‹` chip.
- **Balls.** +X is red, +Y green and +Z blue. The negative axes are light grey and
  **translucent**: a grey ball in front of a coloured one is visibly tinted by it.
- **Lines.** All six axes have a line from the hub. Positive lines are in the axis colour and
  negative lines are grey. There are no letters.
- **Depth.** Balls scale slightly with depth. Hovering a ball grows it a little.
- **Click.** Clicking a ball animates the camera there with an eased rotation of about
  0.5 s, keeping the same target and zoom. Clicking a grey ball gives the opposite view. In
  an aligned view, the facing ball sits in the centre, drawn on top.
- **Clicking the active axis again does nothing.** It does not flip to the opposite view.
- **Drag.** Dragging anywhere on the card orbits.

## How the open-source widgets differ

| | Blender | Godot | three.js / Fennec | ImGuizmo |
|---|---|---|---|---|
| Back-facing balls | Colour mixed toward the background, 50–100%; scale 0.92–1.08 by depth | Alpha 0.35–1 by depth | Negatives 0.2 opacity | Cube faces |
| Negative axes | Fill is 25% axis colour; "-X" label only on hover | Dark inner disc with an axis-colour ring | Black dot | n/a |
| Labels | Bold X/Y/Z, kept upright | X/Y/Z; white on hover | Sprites | Face names |
| Hover | Grey backdrop disc while the pointer is inside | Lighten 25%; grey disc | Fennec: per-axis scale and border | Face highlight |
| Aligned view | Back ball hidden; facing ball not hit-testable, so clicking the centre picks the opposite | One centre ball with swapped style | — | — |
| Snap animation | ~200 ms scaled by angle *(unverified)* | Instant | Constant 2π rad/s via `rotateTowards`; clicks ignored while animating | 40-frame lerp |
| Click vs drag | — | 4 px threshold; a drag never fires the click | Fennec: 10 px threshold | Click cancelled on move |
| Drag sensitivity | Turntable, ~0.4°/px *(unverified)* | Main viewport orbit | Fennec: `delta / width · π`, pitch clamped | 0.01 rad/px |

## Where ours stands

`NavigationGizmo` already has:

- six balls with depth sorting;
- coloured positive axes and grey negative ones;
- tap to snap to a preset, or to its opposite when that preset is active;
- drag to orbit.

It falls short in these places:

1. **Snaps are instant and re-frame.** `ModelView.show(_:)` (`Renderer/ModelView.swift:173`)
   calls `fitCamera()` and then jumps. Both Spline and three.js animate the rotation and keep
   the target and distance.
2. **No sense of depth.** Every ball has the same 0.92 alpha and the same size, so front and
   back look alike. This is the main reason the widget reads as flat next to Spline.
3. **No hover backdrop or labels.** Our hover is only a 1.5 pt stroke.
4. **Negative axes have no lines.** Spline draws grey ones, which makes the triad read as a
   3D object.
5. **The click-vs-drag threshold is 2 pt.** A slightly shaky click orbits instead of
   snapping.
6. **Drag sensitivity uses canvas deltas.** It does not scale with the gizmo's size.

## Recommended design: Spline's look with the best ideas from the others

1. **Animated snap.**
   - Animate azimuth and elevation along the shortest angle. The camera is a turntable, so
     no quaternion slerp is needed.
   - Use about 0.35–0.5 s, ease-in-out, or a constant 2π rad/s so that a small move is quick.
   - Keep the target and distance. Do not call `fitCamera` on a gizmo snap; keep it for the
     menu presets if wanted.
   - Ignore gizmo clicks while an animation runs, and cancel the animation on any canvas
     orbit or zoom.
2. **Depth styling.**
   - Ball scale: 0.9–1.1 by view-z.
   - Front balls opaque; back balls fade toward the panel background, about 40% at the back
     (Blender's mix, Godot's alpha range).
   - Fade the lines the same way.
3. **Spline-style negative axes.**
   - Grey balls, translucent (about 0.6 alpha), so a coloured ball shows through when they
     overlap.
   - Grey lines to the negative balls.
   - "−X" label only on hover (Blender).
4. **Labels.** Optional X/Y/Z inside the positive balls at 8–9 pt radius. Spline has none;
   Blender and Godot do. Off by default to match Spline, and they help accessibility
   screenshots.
5. **Hover.**
   - Grow the hovered ball by about 15% and lighten it.
   - Show a faint backdrop disc while the pointer is over the widget, so it reads as
     draggable.
6. **Aligned views.** Replace the `activePreset` check with Blender's geometric test:
   - When an axis points at the viewer (|xy| ≈ 0), draw only the front ball, in the centre.
   - Make that ball non-hittable, so a centre click picks the ball behind it, which is the
     opposite view.
   - This also works after a drag lands exactly on an axis.
   - Spline does nothing on a re-click; toggling is the better behaviour.
7. **Click vs drag.**
   - 4 pt threshold.
   - Once a drag starts, never fire a snap on release.
   - Clear hover while dragging.
   - Sensitivity `Δ / gizmoWidth · π`, with pitch clamped just short of the poles.
8. **Pole snaps.** For top and bottom, keep the current azimuth rounded to the nearest 90°,
   so the model does not spin on the way up.
9. **Chips above the gizmo, optional.** Spline puts the projection toggle and a collapse
   button there. We already have orthographic; a cube chip next to the gizmo would make the
   ortho/perspective state visible where people look.

Not recommended: ImGuizmo's 26-direction view cube. Corner and edge views add little to a
viewer.

## Verification for the implementation ticket

- Unit tests:
  - depth to alpha and scale mapping;
  - aligned-axis hit test: a centre click returns the opposite axis;
  - shortest-angle azimuth interpolation across ±180°;
  - click-vs-drag threshold.
- On screen: snap animates and keeps the zoom; back balls visibly recede; hover grows the
  ball; a drag of 3 pt still snaps.
