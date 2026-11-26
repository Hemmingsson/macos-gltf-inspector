# Screenshots

The app screenshot supplies the demo window chrome. The three original Finder mockups live in
`assets/mockups/` and must stay separate from generated captures. Do not overwrite
them when capturing release media.

## Animated README demo

Run from the repository root with Node.js 22 or later, FFmpeg, and WebP's `img2webp` installed. Agent skills from `npx skills add heygen-com/hyperframes` live in `.agents/skills/hyperframes*` and drive the CLI.

```sh
cd demo-video
npm ci
npm run export
```

`export.mjs` prefers the skill CLI, then the local `hyperframes` package. It renders each composition at 60 fps and encodes looping WebPs in `docs/`. To render one loop, pass its name, for example `npm run export -- quick-look`. The other names are `demo`, `finder-thumbnails`, and `preview-pane`.

The exporter also writes the full app animation to `docs/demo.mp4`. The hero and Finder loops use a 15-second turntable of AET_Showcase rendered by the app’s Metal renderer. Place `demo-video/AET_Showcase.glb` (meshopt/quantized files are decoded automatically), build with `./scripts/dev.sh install`, then run `./demo-video/turntable.sh` before exporting.

## App screenshot

```sh
./tools/readme/snapshot.sh lumenStudio
./tools/readme/snapshot.sh lumenStudio /absolute/path/to/wallpaper.jpg
```

Builds and opens the fixture, waits for ready logs, captures the window, and writes
`assets/readme/screenshot.png` on a 1920×1080 background. Raw window: `.build/readme/window.png`.

Needs a logged-in desktop and Screen Recording permission for the terminal.
Override the wallpaper with a second argument or `SCREENSHOT_WALLPAPER`.

## Finder demos

Source media for the Finder demos:

- [Thumbnails](../../assets/mockups/finder-thumbnails.png)
- [Preview pane](../../assets/mockups/preview-pane.webp)
- [Quick Look](../../assets/mockups/quick-look.webp)

### Make a new set in the same style

The approved originals are the Finder-window set from commit `c4f0ba2`: a many-model
thumbnail grid, a streetlamp in Quick Look over a Finder list, and a spinning BoomBox
in the preview pane. Quick Look and preview pane are 90-frame animated WebPs, not
stills. Their original editing project is not in Git.

Use native window captures for the replacement chrome and model content. Keep the
transparent exterior, native window shadows and compact crops. Do not add a wallpaper,
white backing card, headings, captions, or simulated HTML Finder controls. Quick Look
keeps the Finder list behind the floating preview. Thumbnail grids should contain a
variety of models, not three copies of one model.

1. On a logged-in Mac, open the installed app once to register the extensions. Use
   licensed model files without private paths or filenames. Arrange Finder in icon
   view for thumbnails, and list view with its preview pane for the preview animation.
   For Quick Look, select a file in Finder and press Space. Keep the pointer outside
   the windows and close popovers and dialogs.
2. Find the visible window IDs with `swift tools/readme/window-ids.swift`. Quick Look may
   appear under a separate system process; choose its visible title, not a PID.
3. Capture with the commands below, substituting the actual IDs. Screen Recording
   permission, Xcode command-line tools and `brew install webp` are required.

```sh
python3 tools/readme/finder-mockups.py thumbnails --finder 123
python3 tools/readme/finder-mockups.py quick-look --finder 123 --quick-look 456
python3 tools/readme/finder-mockups.py preview-pane --finder 789
```

`tools/readme/mockup-layouts.json` stores the 1200 × 760 composition, including the overlapping
Finder and Quick Look windows. Rectangles are `[x, y, width, height]` from the top-left;
captures fit without stretching. Adjust the rectangles if the native window proportions
change. `tools/readme/compose-mockup.swift` composites the transparent PNGs. The Python command
captures a six-second sequence and exports looping lossless WebP with `img2webp`, using
measured capture intervals so slow captures do not speed up the model rotation. Use
`--seconds` or `--fps` to change the capture budget.

Output is staged in `.build/mockups/<kind>-<timestamp>/`, with source PNGs, composed
frames and `capture.json`. The Quick Look backing Finder window is captured once;
only its foreground preview animates. An existing composed PNG sequence can be
re-exported with `--frames-dir /path/to/frames --fps 15`.

Inspect transparency, shadows, filenames, window alignment and the complete animation
loop before replacing the corresponding file in `assets/mockups/`. Verify animation
frames with `webpmux -info path/to/output.webp`. Keep the app version, source model
credits and capture settings with the raw material. Capture commands never overwrite
the approved README assets themselves.

To capture an already-open Release window without rebuilding:

```sh
RELEASE_APP="/absolute/path/to/glTF Inspector.app" ./tools/readme/snapshot.sh
```

The default background is the blue Tahoe wallpaper cached at `.build/readme/tahoe-dark.jpg`.
Pass `-` explicitly to use the built-in gradient. Native capture transparency is preserved;
no white backing frame is added. Keep raw captures and version/source
information with the release evidence.
