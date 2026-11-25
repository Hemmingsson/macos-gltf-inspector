# Screenshots and motion

The README keeps its existing four feature previews: `assets/app_window.webp`,
`assets/finder_thumbnails.png`, `assets/quick_look.webp`, and
`assets/finder_details_pane.webp`. The generated files in `docs/media/` are additional
showcase assets; exporting them does not replace the existing gallery.

The showcase uses **real frames from the app's Metal renderer**, inside HTML mockups of the
app, Quick Look, and Finder. These are illustrative compositions, not screen recordings.
Wallpaper screenshots use the real app window, including its shadow.

## Wallpaper screenshot

```sh
./demo/snapshot.sh uiShowcase
./demo/snapshot.sh uiShowcase /absolute/path/to/wallpaper.jpg
```

Builds and launches the app, waits for the ready logs, captures its front visible document
window, then places it on a 1920×1080 background with rounded transparent corners.
The output is `docs/media/screenshot.png`; the uncomposited capture stays in
`.build/demo/window.png`. The default background is macOS Tahoe Dark, matching the Alfred Netlify preview.
It is cached in `.build/demo/tahoe-dark.jpg`. The screenshot command downloads it from
`https://9to5mac.com/wp-content/uploads/sites/6/2025/06/macOS_26_Dark.jpg` if absent.
Pass a second argument or set `SCREENSHOT_WALLPAPER` to use another image.
Requires a logged-in macOS desktop and Screen Recording permission for the terminal.
The script opens a window and brings the app forward.

## Demo and short loops

Requires Xcode, XcodeGen, Node/npm and FFmpeg and WebP tools (`brew install ffmpeg webp`). HyperFrames is pinned
to 0.8.77 and downloaded through `npx`. GSAP 3.14.2 is vendored in `video/assets/` with its
license header intact.

```sh
./scripts/fetch-test-models.sh  # if Khronos samples are missing
python3 demo/export.py frames  # build ShotRenderer, then render real transparent PNG sequences
python3 demo/export.py demo    # 16-second showcase, four scenes
python3 demo/export.py clips   # individual 4-second loops
# or everything:
python3 demo/export.py all --resolution 4k --fps 60
```

Defaults to 1080p/30fps. Each export writes an MP4 and a looping 1280×720 animated WebP to
`docs/media/`. Frame sequences and build intermediates are ignored by git. The model orbit
has 120 unique frames over four seconds; a 60fps export repeats model frames while animating
the HTML at 60fps. No animation playback is simulated in these turntables.

Edit `shots.json` to choose models separately for `app`, `quicklook`, `preview`, and
`thumbnails`. Paths are relative to the repository root, absolute, or begin with `~/`.
`zoom` controls framing; `view` may be `shaded`, `clay`, `wireframe`, or another supported
ShotRenderer mode. BoomBox is the selected model for all four scenes.
Khronos model licensing travels with the downloaded samples; retain attribution for any
replacement models you publish. Downloaded personal models are never copied into git.

`video/index.html` is the HyperFrames source. Its deterministic `renderAt(t)` selects a
Metal-rendered PNG for each timestamp and updates the HTML chrome and cursor. It uses a
paused GSAP timeline exposed as `window.__timelines.main`. Generated per-shot compositions
are removed after export. Any window mockups should be reviewed when the shipped UI changes.

When a shell runs outside the interactive desktop session, macOS may expose no capturable
app window. In that case, save a window PNG through the connected desktop tool, then run:

```sh
.build/demo/capture compose .build/demo/window.png .build/demo/tahoe-dark.jpg docs/media/screenshot.png
```

The app renderer and its reference images are untouched by this workflow. ShotRenderer is a
development-only target and is never bundled into the app.
