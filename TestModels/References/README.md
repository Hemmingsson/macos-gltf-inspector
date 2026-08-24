# Pixel-diff references

One PNG per Khronos sample, rendered through `WebRendererHost` in still mode. **These files are
the assertions.** `GLTFInspectorTests/PixelDiffTests.swift` re-renders every sample on each run
and compares against them, which is what makes a rendering regression visible now that the
renderer is JavaScript and `xcodebuild` cannot inspect the scene it produced.

`manifest.json` records everything the comparison depends on — canvas size, environment, tone
mapping, the tolerance, and one complete camera pose per model. Nothing that affects the output
is left as a constant in a test file, so changing an assertion means changing a file someone
reviews.

## What "matches" means

Comparison is perceptual, not exact: GPU drivers and renderer versions move pixels by a step or
two, and a suite that flakes gets switched off, which is worse than not having one. Both sides
are flattened onto a fixed mid-grey backdrop and judged on two independent measures:

| Measure | Budget | Catches |
| --- | --- | --- |
| Mean absolute error | 2.0 / 255 | Whole-frame drift — exposure, tone mapping, lighting |
| Pixels off by more than 24, as a share of the frame | 0.5% | Local damage a mean would absorb |

Both matter. A 60x60 block of a 512 frame reads as a mean error of 0.34 — comfortably inside
budget — and is caught only by the second measure. A uniform shift of 4/255 is invisible to the
eye, produces no bad pixels at all, and is caught only by the first.

A mismatch writes `-actual`, `-expected` and `-diff` PNGs to `/tmp/GLTFInspector-pixel-diff/`
(override with `GLB_PIXEL_DIFF_OUT`) and prints all three paths. The diff shows the difference
in red, amplified 8x, over a dimmed copy of the reference, so it says *where* on the model
something moved rather than just that something did.

## Determinism

The camera is replayed from the recorded pose, never re-fitted. `UserCamera.fitViewToScene`
runs exactly once per model, at generation time; a later change to how it frames a scene
therefore cannot silently re-aim the camera and invalidate every PNG here. Canvas size is set
in pixels rather than through `devicePixelRatio`, and environment and tone mapping are set
explicitly rather than inherited from the renderer's defaults.

## Regenerating

Only when a renderer upgrade legitimately changes output:

    ./scripts/regenerate-pixel-references.sh

Then **look at the PNGs** before committing. A wrong reference bakes in a wrong answer for good
— during the first run of this generator every model was mis-framed and one rendered completely
blank, all of which the tests would have happily accepted as correct. `git diff --stat
TestModels/References` tells you which ones moved.

The samples themselves live in `TestModels/Khronos samples/`, which is gitignored; fetch them
with `./scripts/fetch-test-models.sh`. If they are missing the suite **fails** rather than
skipping — a switched-off suite reports green, and an empty run must not be mistakable for a
passing one.
