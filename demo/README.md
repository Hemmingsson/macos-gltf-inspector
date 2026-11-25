# Screenshots

README media must show the real app or Finder — no HTML mockups of the window.

## App hero

```sh
./demo/snapshot.sh lumenStudio
./demo/snapshot.sh lumenStudio /absolute/path/to/wallpaper.jpg
```

Builds and opens the fixture, waits for ready logs, captures the window, and writes
`docs/media/screenshot.png` on a 1920×1080 background. Raw window: `.build/demo/window.png`.

Needs a logged-in desktop and Screen Recording permission for the terminal.
Override the wallpaper with a second argument or `SCREENSHOT_WALLPAPER`.

## Finder demos

Keep these three for the README:

- [Thumbnails](../assets/finder_thumbnails.png)
- [Preview pane](../assets/finder_details_pane.webp)
- [Quick Look](../assets/quick_look.webp)
