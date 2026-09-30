# Test models

Local corpus for glTF Inspector. Open these in the app; tests resolve them via
`GLTFInspectorTests/TestFixtures.swift` (`#filePath`, not the bundle).

| Folder | In git | What |
|---|---|---|
| `Fixture Models/` | yes | Tiny hand-authored / generated glTF. Regen: `python3 scripts/testdata/make_fixtures.py` |
| `Khronos samples/` | no | Pinned Khronos Sample Assets (list + commit: `References/manifest.json`). Fetch: `./scripts/fetch-test-models.sh` |
| `References/` | yes | Per-renderer pixel-diff goldens (`webkit/`, `realitykit/`). See [`References/README.md`](References/README.md) |

Khronos catalogue: https://github.khronos.org/glTF-Assets/ (`#testing`). Referee:
[Sample Viewer](https://github.khronos.org/glTF-Sample-Viewer-Release/). Skip Sketchfab
FBX conversions when judging inspector bugs.
