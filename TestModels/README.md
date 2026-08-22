# Test models

Local corpus for glTF Inspector. Open these in the app; tests resolve them via
`GLTFInspectorTests/TestFixtures.swift` (`#filePath`, not the bundle).

| Folder | In git | What |
|---|---|---|
| `Fixture Models/` | yes | Tiny hand-authored / generated glTF. Regen: `python3 scripts/testdata/make_fixtures.py` |
| `Khronos samples/` | no | Native Khronos Sample Assets (GLB). Fetch: `./scripts/fetch-test-models.sh` |

Khronos catalogue: https://github.khronos.org/glTF-Assets/ (`#testing`). Referee:
[Sample Viewer](https://github.khronos.org/glTF-Sample-Viewer-Release/). Skip Sketchfab
FBX conversions when judging inspector bugs.
