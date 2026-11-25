# Test fixtures

Small, committed glTF/GLB models for tests **and** for exercising the new UI's adaptive behaviour
(docs/design.md — *show only what the model has*). Files live in
[`TestModels/Fixture Models/`](../../TestModels/Fixture%20Models/). Tests reach them through
[`GLTFInspectorTests/TestFixtures.swift`](../../GLTFInspectorTests/TestFixtures.swift), which resolves
paths from the source tree via `#filePath` — **fixtures are not bundled resources**.

Keep them lean and self-contained: geometry is the flat unit triangle, buffers are embedded as
base64 `data:` URIs (single file, no `.bin` sidecar), no downloads. Regenerate the adaptive set with:

```bash
python3 scripts/testdata/make_fixtures.py
```

The `cube/` sidecar is regenerated separately with `python3 scripts/testdata/cube/make_cube.py`.

Native Khronos Sample Assets (not committed): `./scripts/fetch-test-models.sh` →
`TestModels/Khronos samples/`.

## Catalogue

| Fixture | `TestFixtures` | Contents | Exercises (UI state) |
|---|---|---|---|
| `tiny.glb` | `.tiny` | flat 1-triangle GLB | plain static mesh (smallest load) |
| `ui-showcase.glb` | — (`dev.sh run uiShowcase`) | every sidebar section + outliner glyph case | empty groups, typed parents with children, meshes, cameras, lights, materials, skin, morph, animations, two scenes. Regen: `python3 scripts/testdata/make_ui_showcase.py` |
| `cube/cube.gltf` (+bin+png) | `.cube` | textured unit cube, `.gltf` sidecar | plain mesh with a sidecar buffer and image |
| `BoxAnimated/BoxAnimated.glb` | `.boxAnimated` | Khronos animated box | Animations section |
| `invalid/unresolved-mesh.gltf` | `.invalid` | parseable but semantically invalid | validation errors |
| `offcenter/cube-offset.gltf` (+bin+png) | `.offcenter` | authored origin offset | origin gizmo when Center is off |
| `multiscene/two-scenes.gltf` | `.multiScene` | two scenes | Scene switcher appears |
| `lights/punctual-lights.gltf` | `.lights` | KHR_lights_punctual point + directional + spot | Lights section |
| `cameras/persp-and-ortho.gltf` | `.cameras` | one perspective + one orthographic camera | Cameras section, file camera on the canvas |
| `missing-channels/basecolor-only.gltf` | `.missingChannels` | material with baseColor factor only | view-mode menu shortens; material chips omit absent maps |
| `rigged/two-joint-skin.gltf` | `.rigged` | two-joint skin | Skins section |
| `morph/morph-triangle.gltf` | `.morph` | one named morph target ("Blink") | Morph section |
| `corrupt/truncated.glb` | `.corrupt` | valid magic, lying chunk lengths, truncated | hard-failure path — must show `.failed`, never a spinner (AGENTS.md failed-load rule) |

The last fixtures are on-disk stand-ins for adaptive UI and the failure path. The in-memory builders in
[`TestGLBFixtures.swift`](../../GLTFInspectorTests/TestGLBFixtures.swift) build the GLB bytes tests
need without a file on disk.

`appcast-sample.xml` is a Sparkle update-feed fixture, unrelated to model loading.

## Lumen Studio — compact showcase

`Lumen Studio.glb` is an original, self-contained demo asset (MIT), generated with
`python3 scripts/testdata/make_demo_studio.py`. Open with `./scripts/dev.sh run lumenStudio`.

- **Scene 1 — Display:** a porcelain/brass plinth, petrol-enamel lamp, terracotta morph
  pebble, brass sphere, and a blue two-joint skinned sculpture.
- **Scene 2 — Form studies:** the same compact display without the lamp, sharing the same
  mesh, camera, and skin assets. Both scenes can play the same animation.
- **Inspector coverage:** named groups and meshes, six visible PBR materials, perspective
  camera, spot/point/directional lights, Squash morph target, two-joint skin, and the
  `Breathe & sway` animation (morph twists + joint rotation).

The camera and lights appear as native gizmos when enabled; their scene nodes are authored
camera/light objects, not decorative proxy geometry. Select the named nodes or materials to
show the corresponding inspector. All geometry is procedural; no external assets are needed.

The delivered outliner uses finished objects: Plinth and Table lamp each contain multiple
material primitives, not separate construction-part nodes. For the hero, select
**Brushed champagne brass** under Materials to show PBR details; collapse Lighting and
Armature and frame the full display. Lights have no surface material.
