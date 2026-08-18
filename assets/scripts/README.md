# Mockup preview generator

Renders a spinning 3D model into the green (`#00FF00`) viewport area of each macOS
window mockup in `../macOS_mockups/`, and writes one looping animated **WebP** per window
to `../exported/` (`app_window.webp`, `finder_details_pane.webp`, `quick_look.webp`).
Green-less mockups (e.g. `finder_thumbnails.png`) are copied through as a plain still.

This folder is **not** part of the app — it's just asset tooling.

## Run

```sh
cd assets/scripts
npm i          # installs puppeteer-core, sharp, model-viewer (no browser download)
npm start
```

Requirements: Node, and **Google Chrome** installed at
`/Applications/Google Chrome.app` (edit `CHROME` in `make-previews.mjs` otherwise).
`npm start` renders with headless Chrome — nothing extra is downloaded except the sample
models (first run only; needs internet).

## How it works

1. Detects the green rectangle in each mockup (per-pixel mask → rounded corners respected).
2. Headless Chrome + `<model-viewer>` renders `FRAMES` turntable frames (360°) sized to that rectangle.
3. `sharp` composites each frame into the mockup's green area over white, then encodes an animated WebP.

All three windows use the same `FRAMES`/`FPS`, so every model spins at the same speed.

## Tweaks (top of `make-previews.mjs`)

- `JOBS` — which model goes in which window. Use a Khronos sample name (auto-downloaded)
  or drop your own `.glb` in `models/` and reference its filename.
- `FRAMES` / `FPS` — smoothness and spin speed.
- `MAX_WIDTH` / `WEBP_QUALITY` — file-size vs. quality.
