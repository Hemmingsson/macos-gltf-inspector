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

| Fixture | `TestFixtures` | Contents | Exercises (UI state) | Used by |
|---|---|---|---|---|
| `tiny.glb` | `.tiny` | flat 1-triangle GLB | plain static mesh (smallest load) | LoaderMaterial, StillRenderProof |
| `cube/cube.gltf` (+bin+png) | `.cube` | textured unit cube, `.gltf` sidecar | plain mesh via skip-packing path | Validator, ModelDimensions, PipelineReport, StillCameraPose, StillRenderProof |
| `BoxAnimated/BoxAnimated.glb` | `.boxAnimated` | Khronos animated box | playback bar + Animations section | PreviewClip |
| `invalid/unresolved-mesh.gltf` | `.invalid` | parseable but semantically invalid | validation errors / pipeline report | Validator |
| `offcenter/cube-offset.gltf` (+bin+png) | `.offcenter` | authored origin offset | origin gizmo when Center is off | — (available for UI) |
| `multiscene/two-scenes.gltf` | `.multiScene` | two scenes | Scene switcher appears | — (available for UI) |
| `lights/punctual-lights.gltf` | `.lights` | KHR_lights_punctual point + directional + spot | Lights section, file-vs-studio | — (available for UI) |
| `cameras/persp-and-ortho.gltf` | `.cameras` | one perspective + one orthographic camera | Cameras section | — (available for UI) |
| `missing-channels/basecolor-only.gltf` | `.missingChannels` | material with baseColor factor only | view-mode menu shortens; material chips omit absent maps | — (available for UI) |
| `missing-texture/missing-image.gltf` | `.missingTexture` | valid JSON, missing image URI | convert `missingTexture` error | ConvertProblemTests |
| `rigged/two-joint-skin.gltf` | `.rigged` | two-joint skin | skeleton controls | — (available for UI) |
| `morph/morph-triangle.gltf` | `.morph` | one named morph target ("Blink") | morph controls | — (available for UI) |
| `corrupt/truncated.glb` | `.corrupt` | valid magic, lying chunk lengths, truncated | hard-failure path — must show `.failed`, never a spinner (AGENTS.md pitfall 2) | PipelineHoleTests |

The last fixtures are on-disk stand-ins for adaptive UI and convert honesty. The in-memory builders in
[`TestGLBFixtures.swift`](../../GLTFInspectorTests/TestGLBFixtures.swift) still cover byte-level edge
cases (primitive modes, malformed accessors, instancing) that don't belong on disk.

`appcast-sample.xml` is a Sparkle update-feed fixture, unrelated to model loading.
