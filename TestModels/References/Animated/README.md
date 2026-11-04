# Animated reference images

Khronos Sample Renderer stills at a fixed animation time. The PNGs next to `manifest.json` are the
assertions. `AnimatedReferenceTests` draws the same camera and look with Metal and compares them.

These are not rest poses. Rest stills stay in the parent folder (`TestModels/References/*.png`).
Nothing in this folder is an input to `./scripts/regenerate-pixel-references.sh`, and that script
must not be pointed here: it renders with Metal and rewrites the rest set.

## What each file is

| PNG | Model | Clip | Time |
| --- | --- | --- | --- |
| `AnimatedMorphCube-t0.5.png` | `AnimatedMorphCube` | 0 (morph weights) | 0.5 s |
| `AnimatedMorphCube-t1.0.png` | `AnimatedMorphCube` | 0 | 1.0 s |
| `SimpleSkin-t1.0.png` | `SimpleSkin` | 0 (joint rotation) | 1.0 s |

The morph cube reuses the rest still's camera. `SimpleSkin` has no rest still; its camera is
whatever the Khronos page measured (fit, then azimuth 25° / elevation −18°) on the capture that
wrote the PNG. `animation.time` is greater than 0 because the pinned `AnimationTimer` treats
`fixedTime` 0 as unset and falls through to the wall clock.

The look matches the rest manifest: 512², neutral environment, rotation 90, exposure 0,
Khronos PBR Neutral, transparent clear. Comparison uses the same `tolerance` and the same
mid-grey flatten as the rest stills.

## Produce or refresh the PNGs

From the repo root, with Google Chrome installed at
`/Applications/Google Chrome.app`:

```bash
./scripts/fetch-test-models.sh
./scripts/capture-khronos-animated-references.mjs
```

The capture script checks out the vendored renderer
(`10201cb:RendererWebKit/web-renderer`, the minify of `f1fd1af:Vendor/web-renderer`) and
`neutral.hdr` into `.build/khronos-anim-capture/`, then loads `scripts/khronos-animated-references/capture.html`
in headless Chrome. It does not launch glTF Inspector.

Success is one line per entry (`opaque` well above 0, and a WebGL renderer string) plus
`wrote 3 PNGs`. The script refuses to continue if a posed frame matches that model's rest
frame, or if the two morph times match each other. A missing camera is filled in
`manifest.json` from the page; an existing camera is replayed and left as written.

A missing PNG fails `posedFramesMatchKhronosReferences`. Do not fill the gap with a Metal
screenshot.
