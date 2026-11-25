# Screenshots and Finder clips

**App media must show the real app UI.** Do not recreate the app window in HTML.
The README uses `docs/media/screenshot.png` above three Finder feature previews.
Keep the original Quick Look, preview-pane, and thumbnail assets in `assets/`.
The obsolete app loop and the combined mock-app demo have been removed.

## Real app screenshot

```sh
./demo/snapshot.sh lumenStudio
./demo/snapshot.sh lumenStudio /absolute/path/to/wallpaper.jpg
```

The command builds and opens a fixture, waits for ready logs, then captures its window.
It places the capture on a 1920×1080 background with rounded corners and a shadow.
The raw window stays in `.build/demo/window.png`; output is `docs/media/screenshot.png`.
The default background is the macOS Tahoe Dark image used by Alfred Netlify's preview.
It is cached in `.build/demo/tahoe-dark.jpg`. If absent, the script downloads it from
`https://9to5mac.com/wp-content/uploads/sites/6/2025/06/macOS_26_Dark.jpg`.
Pass a second argument or set `SCREENSHOT_WALLPAPER` to use another image.
Requires a logged-in macOS desktop and terminal Screen Recording permission.
The script opens a window and brings the app forward.

When the shell cannot see the desktop session, save a verified window capture through
the connected desktop tool. Check the document title, visible model, and inspector before composing:

```sh
swiftc demo/capture.swift -o .build/demo/capture
.build/demo/capture compose .build/demo/window.png .build/demo/tahoe-dark.jpg docs/media/screenshot.png
```

For the hero, use the compact Lumen Studio fixture. Keep the mix of scene types and
Materials, Skins, Animations, and Morphs visible. Select a material to show its PBR facts.
Never reuse a capture from an older scene or a different window.

## Quick Look, preview pane, and thumbnails

These three contexts may use HTML mockups with real Metal-rendered model frames.
They are illustrations, not screen recordings. No mock app-window scene is supported.

Requires Xcode, XcodeGen, Node/npm, FFmpeg, and WebP tools (`brew install ffmpeg webp`).
HyperFrames is pinned to 0.8.77. Vendored GSAP 3.14.2 retains its license header.

```sh
python3 demo/export.py frames  # build ShotRenderer and render model sequences
python3 demo/export.py clips   # export the three four-second clips
python3 demo/export.py all --resolution 4k --fps 60
```

Default output is 1080p/30fps MP4 plus looping 1280×720 WebP in `docs/media/`.
The orbit has 120 unique frames over four seconds. A 60fps export repeats model frames
while animating the HTML at 60fps. It does not play authored model animation.
Build intermediates and frame sequences are ignored by Git.

Edit `shots.json` for `quicklook`, `preview`, and `thumbnails`. Model paths may be relative
to the repo, absolute, or start with `~/`. `zoom` sets framing; `view` selects a renderer mode.
Keep each model's terms and attribution when publishing. Personal model files stay out of Git.
`video/index.html` uses deterministic `renderAt(t)` and `window.__timelines.main`.
Generated clip compositions are removed after export. Review mock chrome when macOS changes.
ShotRenderer is a development target. The app renderer and reference images are unchanged.
