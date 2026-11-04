# Reference images

The renderer's accuracy baseline. Every PNG here was rendered by the Khronos glTF Sample Renderer
itself (its web page, which this app embedded before the Metal port replaced it), so the tests
hold the Metal renderer to Khronos's own output.

**These files are the assertions.** `./scripts/dev.sh test` renders every case with the Metal
renderer and compares it against its PNG with one comparator (`PixelDiff`, with the manifest and
loops in the other `GLTFInspectorTests/PixelDiff*.swift` files).

| Set | Cases | How each is rendered |
| --- | --- | --- |
| `<sample>.png` | One per pinned Khronos sample in `manifest.json` | `MetalRenderer` at the manifest look, from the recorded camera pose (`PixelDiffMetalTests`) |
| `Features/<case>.png` | Overlays, wireframe, orthographic, field of view, file cameras, a second scene, punctual lights, every debug channel, every environment and tone mapping | `ModelView` with its own fit, orbited to 30° / −20°, at 256² (`FeatureReferenceTests`, case list in `PixelDiffMetalTests.swift`) |

## The manifest

`manifest.json` is the pinned sample list and records everything the comparison depends on:

- `samples`: the upstream repository and the commit every sample is fetched at.
- `look`: image size, environment, environment rotation, exposure, tone mapping and background,
  in the Khronos renderer's terms. `environmentRotationDegrees: 90` is the Sample Viewer's default
  view, which `RenderLook` yaw 0 means.
- `tolerance`: the comparison budget.
- `entries`: per sample, the upstream `source` folder, the `files` to fetch (primary model first),
  `requires` (the file's `extensionsUsed` plus `core:` feature tags, checked against the file) and
  one complete `camera` pose.

Verification replays the recorded pose; the camera is never re-fitted, so a change to the fit
heuristic cannot re-aim the camera and invalidate every PNG.

## What "matches" means

Both sides are flattened onto a fixed mid-grey backdrop and judged on two measures:

| Measure | Budget | Catches |
| --- | --- | --- |
| Mean absolute error | 1.0 / 255 | Whole-frame drift: exposure, tone mapping, lighting |
| Pixels off by more than 16, as a share of the frame | 0.1% | Local damage a mean would absorb |

A mismatch writes `-actual`, `-expected` and `-diff` PNGs to `/tmp/GLTFInspector-pixel-diff/`
(override with `GLB_PIXEL_DIFF_OUT`). The diff shows the difference in red, amplified 8×, over a
dimmed copy of the reference.

## Adding a sample or regenerating

Regenerating renders with the Metal renderer, so the regenerated PNGs are no longer Khronos's
output. Do it only to add a sample or after a deliberate renderer change, and compare every
changed image with the [Khronos Sample Viewer](https://github.khronos.org/glTF-Sample-Viewer-Release/)
first.

1. To add a sample, add `name`, `source` and `files` to `manifest.json` `entries`, then
   `./scripts/fetch-test-models.sh`.
2. `./scripts/regenerate-pixel-references.sh` records poses and `requires`, and rewrites every
   PNG (`--measure-noise` prints the run-to-run noise floor instead).
3. Look at the PNGs; `git status TestModels/References` lists the ones that moved.

The generator is gated on a sentinel file (`REGENERATE`, `MEASURE_NOISE`) because `xcodebuild
test` does not forward the shell environment.

The samples live in `TestModels/Khronos samples/` (gitignored). If a pinned sample is missing the
suite **fails** rather than skipping: an empty run must not look like a passing one.
