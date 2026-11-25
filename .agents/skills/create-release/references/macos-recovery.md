# macOS release failure recovery

Use observed errors to choose a bounded recovery. These are lessons from the T3 release history, not automatic cleanup actions.

## Finder shows generic icons or only cached previews

Registration is not proof of execution. Inspect both elected PreviewExtension and ThumbnailExtension with `pluginkit -m -v`, then unified logs for the actual extension path selected by Quick Look/ThumbnailsAgent. An old `dist/archive`, DerivedData, or `.build` app can steal selection even when pluginkit lists `/Applications`.

Unregister only confirmed stale copies using `lsregister -u` / supported plugin commands, register the intended installed app, and reset the relevant cache/agent if needed. Preserve archives and unrelated apps; do not blanket-delete registrations or kill all apps. Check Finder's “Show icon preview” setting. Verify a fresh valid GLB and sidecar glTF, not just an already cached cube. Invalid files may legitimately retain generic icons. Fix wrong selection before changing rendering code.

## Tests end with SIGTERM or exit 0

Stop competing app launches/installs/quits and inspect the result bundle. Do not label a process termination a pixel mismatch. The history also exposed test-host detection relying only on `XCTestConfigurationFilePath`; confirm current lifecycle behavior before blaming external interference. Fix confirmed lifecycle defects and rerun affected tests, then the required full acceptance run.

## Logs say ready but no window is visible

Cold Launch Services delivery differs from argv launch. Check actual windows, pending open events, welcome-window dismissal, and last-window termination. For captures, bind to the exact app bundle/PID. A document may be in another Space: the capture helper supports all Spaces and an optional exact title. Refresh UI state after app/window changes; do not keep using stale IDs.

## Recording or SVG rendering is wrong

Reject black recordings. Timed captures of the actual native window can be encoded using recorded elapsed times; document effective frame rate and duplication. Never replace failed native captures with renderer frames while calling them recordings. Inspect the whole video; if playback tooling is unavailable, inspect every frame plus full decode and explicitly record that fallback. Never claim real-time playback was verified.

Some rasterizers mishandle SVG CSS and dark mode. Use a CSS-capable local renderer and inspect both appearances. Preserve editable specs; fix affected labels/contrast rather than rebuilding the documentation system.

## Reuse without confusing candidates

An old notarized 1.1 ZIP is not a new 1.0 release. A proper export can remove debugging entitlements and sign Sparkle helpers that a plain Release build leaves unsuitable for distribution. Recheck the final export, not assumptions from its build settings. Preserve successful notarization IDs and archive checksums so retries resume the right candidate.
