---
name: macos-testing
description: Verify changes to glTF Inspector on a real macOS window, in tests, and through its Quick Look and Finder extensions. Prefer a linked T3 remote Mac (Big Mac) and BigMac when available.
---

# Test glTF Inspector

Run commands from the repository root. This app requires macOS 26+, Xcode, XcodeGen, and Apple Silicon.

## Where to run

Always prefer a linked T3 remote Mac when one answers:

1. Call `t3_environment_links`.
2. Pick a reachable Mac (`status: "reachable"`). Prefer a host labeled Big Mac / datorn / desktop Mac over this agent host when both exist.
3. If none is linked or reachable, call `t3_environment_link` with hint `bigmac` (or the name the user gave) and stop until it links — do not fall back silently for on-screen or UI work that needs a WindowServer session.
4. Run the acceptance work on that host with `delegate_task`, `role: "test"`, `target.environmentId` set to that link, and a self-contained task that follows this skill. Mention the child's thread `link` in the reply.
5. Use local only when no remote Mac is available **and** this machine itself has an interactive macOS desktop with WindowServer. Unit/reference tests may still run locally when Metal and samples are present.

T3 `device_*` tools are for iOS Simulator / Android Emulator panels. Do **not** use them for this macOS app. Drive the remote desktop Mac through the environment link + shell / BigMac on that host.

## BigMac first

Prefer BigMac (`bigmac` on `PATH`) for build, launch, test, screenshot, logs, and report. If `.bigmac.json` is missing:

```sh
bigmac init --project GLTFInspector.xcodeproj --scheme GLTFInspector --bundle-id lol.mattias.gltf-inspector
```

Typical commands (add `--json` when parsing):

```sh
bigmac doctor
bigmac test
bigmac test unit
bigmac test ui
bigmac test GLTFInspectorTests/ModelCanvasControllerTests
bigmac run --args "--fixture" "cube"
bigmac screenshot --window "glTF"
bigmac logs --since 30s
bigmac stop
bigmac report   # or read .artifacts/tests/latest/
```

Artifacts land under `.artifacts/` (`tests/latest` symlink, screenshots, logs). On failure read `.artifacts/tests/latest/failures.md`; otherwise `report.md`. When BigMac returns a pending report receipt, embed the planned preview path labeled pending and continue — do not poll for the file.

If `bigmac` is not installed on the chosen host, fall back to the project scripts below. Do not invent a second test harness.

## Tests

```sh
./scripts/dev.sh test
# or, with BigMac:
bigmac test
```

The suite includes unit tests and Metal reference-image tests. To run one suite:

```sh
./scripts/dev.sh test -only-testing:GLTFInspectorTests/ModelCanvasControllerTests
```

Reference tests require the pinned Khronos files. Fetch them first when `TestModels/Khronos samples/` is missing:

```sh
./scripts/fetch-test-models.sh
```

Missing samples fail the tests; they are not skipped. The committed PNGs in `TestModels/References/` are Khronos Sample Renderer output. Pixel mismatches write `-actual`, `-expected`, and `-diff` files to `/tmp/GLTFInspector-pixel-diff/`. Only regenerate references for a new sample or a deliberate renderer change:

```sh
./scripts/regenerate-pixel-references.sh
```

Look at every changed PNG before committing. Do not use regeneration to make a failing test pass.

## On-screen checks

Fixtures are listed in `scripts/fixtures.manifest.json` and live under `TestModels/Fixture Models/`. Use an ID from that manifest:

```sh
./scripts/dev.sh fixtures
./scripts/dev.sh run cube
# or:
bigmac run --args "--fixture" "cube"
```

`run` installs/launches the debug app. The app writes `.build/logs/debug.log` (BigMac also keeps `.artifacts/logs/`). For one window, expect exactly one `open start`, then `open ready` or `open failed`, and `canvas ready` or `canvas failed`. There must be no `Modifying state during view update` warning.

Set `GLTF_FULLSCREEN=1` when the full-screen window is useful:

```sh
GLTF_FULLSCREEN=1 ./scripts/dev.sh run uiShowcase
```

After the window is visible, capture without a prompt. Prefer BigMac (window capture, no click):

```sh
bigmac screenshot --window "glTF"
```

Fallback when BigMac is absent (`GLTF_FULLSCREEN=1` makes the app fill the display):

```sh
screencapture -x /tmp/gltf-inspector-window.png
```

Avoid `screencapture -w`: it waits for a mouse click. Inspect the PNG for layout and state, not just the logs. Embed the screenshot path in the reply.

`./scripts/dev.sh uitest` / `bigmac test ui` runs real-window XCUITests and takes keyboard focus — run only on the remote Mac (or a machine that can be left alone). `./scripts/dev.sh bench` runs load / first-still / GPU timings on an idle machine.

## Quick Look and thumbnails

`qlmanage -p` and `qlmanage -t` can hang without a WindowServer session. Prefer the in-process end-to-end coverage in `GLTFInspectorTests/` for those paths. On a desktop Mac with WindowServer, reset the Quick Look cache with:

```sh
qlmanage -r
pluginkit -m -i lol.mattias.gltf-inspector.PreviewExtension
pluginkit -m -i lol.mattias.gltf-inspector.ThumbnailExtension
```

The bundle IDs are defined in `project.yml`. A registered extension still needs a locally installed app; `./scripts/verify.sh` checks both installed extensions.

## Done means

- Work ran on a reachable T3 remote Mac when one was linked; otherwise the limitation is stated.
- `bigmac test` or `./scripts/dev.sh test` passes in the foreground, with Khronos samples present.
- Any relevant fixture opens with the expected log sequence and no state-update warning.
- On-screen evidence includes a BigMac (or fallback) screenshot that was inspected.
- Changed reference PNGs were inspected, or no reference changed.
- UI tests or benchmarks were run when the change affects them.
- Quick Look and thumbnail behavior was tested in-process, or on a desktop with WindowServer.
