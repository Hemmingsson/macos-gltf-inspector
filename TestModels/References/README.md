# Pixel-diff references

The proof baseline every renderer refactor is diffed against. One PNG per pinned Khronos sample
**per renderer**:

| Folder | Rendered by |
| --- | --- |
| `webkit/` | `WebRendererHost` in still mode (the Khronos glTF Sample Renderer page) |
| `realitykit/` | `EntityLoader.loadThumbnail` → `StillRenderer` (the RealityKit still path) |

**These files are the assertions.** `PixelDiffWebKitTests` (`GLTFInspectorTests/WebKit/`) and
`PixelDiffRealityKitTests` (`GLTFInspectorTests/RealityKit/`) re-render every sample on each run
and compare each against its own folder with one renderer-neutral comparator (`PixelDiff`, with
the manifest and loops in `GLTFInspectorTests/PixelDiff*.swift` at the test root). The two renderers are never
compared with each other: they have different tone mappers and light units, so a cross-renderer
gate would only measure that. Goldens catch *regressions*; they do not prove correctness.

## The manifest

`manifest.json` is the single pinned sample list and records everything the comparison
depends on:

- `samples` — the upstream repository and the commit every sample is fetched at.
- `look` — canvas size, environment, environment rotation, exposure, tone mapping and
  background, all sent explicitly instead of inherited from a renderer default.
- `tolerances` — the comparison budget per renderer.
- `entries` — per sample: upstream `source` folder, the `files` to fetch (primary model first),
  `requires` (the file's `extensionsUsed` plus `core:` feature tags, checked against the file by
  `recordedFeaturesMatchTheFiles`), and one complete `camera` pose.

`look` values are in the WebKit page's terms. `environmentRotationDegrees: 90` is the Khronos
Sample Viewer default view, which the web goldens have always been rendered at; a future
`RenderLook` yaw of 0 maps to it. How RealityKit maps each look field (IBL-only exposure,
system tone map, native IBL yaw 0, opaque background) is the table on `PixelDiffRealityKit` in
`GLTFInspectorTests/RealityKit/PixelDiffRealityKitTests.swift`.

Both renderers replay the same recorded pose: the camera is never re-fitted at verification
time, so a change to either renderer's framing heuristic cannot re-aim the camera and
invalidate every PNG here.

## What "matches" means

Both sides are flattened onto a fixed mid-grey backdrop and judged on two independent measures:

| Measure | Budget (both renderers) | Catches |
| --- | --- | --- |
| Mean absolute error | 1.0 / 255 | Whole-frame drift — exposure, tone mapping, lighting |
| Pixels off by more than 16, as a share of the frame | 0.1% | Local damage a mean would absorb |

Both matter. A 40x40 block of a 512 frame barely moves the mean and is caught only by the
second measure. A uniform shift of 4/255 produces no bad pixels at all and is caught only by the
first.

**Where the budget comes from.** The run-to-run noise floor was measured at zero for both
renderers on the reference machine (21 samples × 3 fresh renders + the committed golden from a
separate process: mean 0, max channel 0). So the budget is not absorbing noise; it is the
smallest margin that still passes a one-step whole-frame drift (a driver or OS update) and a
little antialiasing movement on edges. Re-measure after a machine, macOS or GPU change:

    ./scripts/regenerate-pixel-references.sh --measure-noise

A mismatch writes `-actual`, `-expected` and `-diff` PNGs to
`/tmp/GLTFInspector-pixel-diff/<renderer>/` (override with `GLB_PIXEL_DIFF_OUT`) and prints all
three paths. The diff shows the difference in red, amplified 8x, over a dimmed copy of the
reference.

## Adding a sample

1. Add `name`, `source` (upstream folder) and `files` to `manifest.json` `entries`.
2. `./scripts/fetch-test-models.sh`
3. `./scripts/regenerate-pixel-references.sh` — records the pose and `requires`, renders both
   renderers.

## Regenerating

Only when a renderer change legitimately changes output:

    ./scripts/regenerate-pixel-references.sh              # webkit (re-records poses) + realitykit
    ./scripts/regenerate-pixel-references.sh realitykit   # one renderer

Then **look at the PNGs** before committing. A wrong reference bakes in a wrong answer for good.
`git status TestModels/References` tells you which ones moved. The generator is gated on a
sentinel file (`REGENERATE`, `MEASURE_NOISE`), not an environment variable, because
`xcodebuild test` does not forward the shell environment.

The samples live in `TestModels/Khronos samples/`, which is gitignored; fetch them with
`./scripts/fetch-test-models.sh`. If a pinned sample is missing, the suite **fails** for both
renderers rather than skipping — a switched-off suite reports green, and an empty run must not
be mistakable for a passing one.

## Known RealityKit baseline gaps (recorded, not fixed)

The RealityKit goldens pin today's behaviour, including visible errors that later seams fix:

- `TextureEncodingTest` — the four columns must match; on RealityKit the textured emissive
  spheres are grey and the "custom gamma" / "ICC profile" base colours are black and red.
- `PointLightIntensityTest` — the point lights barely register on the panels.
- `BoomBox` — much darker than web; the emissive display is missing.
- Background — the requested mid-grey clear colour comes out dark grey (system tone map).
