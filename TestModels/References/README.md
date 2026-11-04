# Pixel-diff references

The proof baseline every page change is diffed against: one PNG per pinned Khronos sample,
rendered by `WebRendererHost` in still mode (the Khronos glTF Sample Renderer page).

**These files are the assertions.** `PixelDiffWebKitTests` re-renders every sample on each run
and compares it against its PNG here with one comparator (`PixelDiff`, with the manifest and loops
in the other `GLTFInspectorTests/PixelDiff*.swift` files). Goldens catch *regressions*; they do
not prove correctness.

## The manifest

`manifest.json` is the single pinned sample list and records everything the comparison
depends on:

- `samples` — the upstream repository and the commit every sample is fetched at.
- `look` — canvas size, environment, environment rotation, exposure, tone mapping and
  background, all sent explicitly instead of inherited from a page default.
- `tolerance` — the comparison budget.
- `entries` — per sample: upstream `source` folder, the `files` to fetch (primary model first),
  `requires` (the file's `extensionsUsed` plus `core:` feature tags, checked against the file by
  `recordedFeaturesMatchTheFiles`), and one complete `camera` pose.

`look` values are in the page's terms. `environmentRotationDegrees: 90` is the Khronos Sample
Viewer default view, which the goldens have always been rendered at; `RenderLook` yaw 0 maps to
it (`PixelDiffWebKit` sends yaw = rotation − 90 through the page's `apply`).

Verification replays the recorded pose: the camera is never re-fitted at verification time, so a
change to the page's framing heuristic cannot re-aim the camera and invalidate every PNG here.

## What "matches" means

Both sides are flattened onto a fixed mid-grey backdrop and judged on two independent measures:

| Measure | Budget | Catches |
| --- | --- | --- |
| Mean absolute error | 1.0 / 255 | Whole-frame drift — exposure, tone mapping, lighting |
| Pixels off by more than 16, as a share of the frame | 0.1% | Local damage a mean would absorb |

Both matter. A 40x40 block of a 512 frame barely moves the mean and is caught only by the
second measure. A uniform shift of 4/255 produces no bad pixels at all and is caught only by the
first.

**Where the budget comes from.** The run-to-run noise floor was measured at zero on the
reference machine (21 samples × 3 fresh renders + the committed golden from a separate process:
mean 0, max channel 0). So the budget is not absorbing noise; it is the smallest margin that
still passes a one-step whole-frame drift (a driver or OS update) and a little antialiasing
movement on edges. Re-measure after a machine, macOS or GPU change:

    ./scripts/regenerate-pixel-references.sh --measure-noise

A mismatch writes `-actual`, `-expected` and `-diff` PNGs to `/tmp/GLTFInspector-pixel-diff/`
(override with `GLB_PIXEL_DIFF_OUT`) and prints all three paths. The diff shows the difference in
red, amplified 8x, over a dimmed copy of the reference.

## Adding a sample

1. Add `name`, `source` (upstream folder) and `files` to `manifest.json` `entries`.
2. `./scripts/fetch-test-models.sh`
3. `./scripts/regenerate-pixel-references.sh` — records the pose and `requires`, renders the PNG.

## Regenerating

Only when a page change legitimately changes output:

    ./scripts/regenerate-pixel-references.sh

Then **look at the PNGs** before committing. A wrong reference bakes in a wrong answer for good.
`git status TestModels/References` tells you which ones moved. The generator is gated on a
sentinel file (`REGENERATE`, `MEASURE_NOISE`), not an environment variable, because
`xcodebuild test` does not forward the shell environment.

The samples live in `TestModels/Khronos samples/`, which is gitignored; fetch them with
`./scripts/fetch-test-models.sh`. If a pinned sample is missing, the suite **fails** rather than
skipping — a switched-off suite reports green, and an empty run must not be mistakable for a
passing one.
