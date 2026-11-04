# Test fixtures

Small, committed glTF/GLB models for tests **and** for exercising the new UI's adaptive behaviour
(DESIGN.md — *show only what the model has*). Files live in
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
| `corrupt/truncated.glb` | `.corrupt` | valid magic, lying chunk lengths, truncated | hard-failure path — must show `.failed`, never a spinner (AGENTS.md pitfall 2) |

The last fixtures are on-disk stand-ins for adaptive UI and the failure path. The in-memory builders in
[`TestGLBFixtures.swift`](../../GLTFInspectorTests/TestGLBFixtures.swift) build the GLB bytes tests
need without a file on disk.

`appcast-sample.xml` is a Sparkle update-feed fixture, unrelated to model loading.
