# glTF Inspector (`webkit-renderer`)

macOS 26+ Quick Look + Finder thumbnails for `.glb` / `.gltf`. Host **`GLTFInspector`** embeds
`PreviewExtension` and `ThumbnailExtension`. **On-screen pixels** come from one
`WKWebView` page running the Khronos glTF Sample Renderer (`Shared/WebRenderer/` +
`Vendor/web-renderer/`). Goal: closest practical **1:1** with web glTF — same renderer in the
window, Quick Look, and Finder icons.

The host still runs **`EntityLoader` → GLTFKit2 → RealityKit convert** for the sidebar
document, morphs, animations, and a few controls. That path does not draw the model when
`webCanvasURL` is set.

**New features, UX, or chrome:** read [`DESIGN.md`](DESIGN.md) first — product principles, not
layout spec (code wins on what ships where).

## Layout

| Path | Role |
| --- | --- |
| `PreviewUI/` | Host chrome over seam protocols. **Do not import `Shared/` or `GLTFCore`.** |
| `GLTFCore/` | Extension-safe framework: glTF file model (JSON document, GLB read side), validator, stats, App Group settings + `AppLook`, bundled Khronos HDRs (`KhronosEnvironments.bundledDirectory`), PNG writer, JSON model bounds (`ModelBounds`), neutral render values (`RenderLook`, `RenderViewMode`, `CameraPreset`, `RendererFeature`; host maps PreviewUI ↔ core in `Engine/EngineCoreMapping.swift`). No RealityKit / WebKit / AppKit / PreviewUI. Embedded once in the host; the extensions link it. |
| `GLTFInspector/Engine/` | `Engine*` adapters — seam mapping only; no PreviewUI rewrites. |
| `GLTFInspector/HostShellRootView.swift` | Document window: shell + adapters + `PreviewView` (`webCanvasURL`). |
| `GLTFInspector/HostSidebarModel.swift` | Selection, scenes, variants — JSON-backed `GLTFSessionDocument`. |
| `Shared/WebRenderer/` | `WebRendererHost`, scheme handler, command bridge, `WebPreviewCanvas`. |
| `Vendor/web-renderer/` | The one `viewer.html` + Khronos bundle. Do not fork a second page. |
| `Shared/PreviewView.swift` | Web canvas when `webCanvasURL` is set; else `PreviewScene` (RK fallback). |
| `Shared/PreviewScene.swift` | RealityView fallback. Unused when the web canvas is showing. |
| `Shared/EntityLoader.swift` + `Shared/Convert/` | Host inspector data, tests, RK fallback — not Finder/QL pixels. |
| `PreviewExtension/` | Quick Look: `webCanvasURL` only, no convert. |
| `ThumbnailExtension/` | Still render via `WebRendererHost(.still)`. |
| `TestModels/References/` | Pinned sample manifest + per-renderer pixel-diff goldens (`webkit/`, `realitykit/`). |

Ship **`GLTFInspector/`** — not legacy `GLBPreview/`. Product on **`main`** is still RealityKit;
this worktree is throwaway until merged.

## Commands & build

```bash
./scripts/dev.sh install          # worktree-aware → .build/ (+ /Applications on main); no open
./scripts/dev.sh test             # xcodegen + xcodebuild test into this branch's DerivedData (args → xcodebuild)
./scripts/dev.sh run cube         # install + launch fixture; logs → .build/logs/debug.log
./scripts/dev.sh logs             # tail debug log (agents: read .build/logs/debug.log)
./scripts/build.sh                # install + open /Applications + verify (explicit ship check)
./scripts/build.sh --install-only # same as dev.sh install (VS Code Build task)
./scripts/verify.sh               # installed app + pluginkit
./scripts/proof.sh                # StillRenderProofTests (RK convert still) + optional qlmanage
./scripts/release.sh              # Developer ID + notary + Sparkle + gh release
./scripts/vendor-khronos-environments.sh
./scripts/fetch-test-models.sh    # pinned Khronos samples (manifest.json) → TestModels/Khronos samples (gitignored)
./scripts/regenerate-pixel-references.sh [webkit|realitykit]  # rewrite goldens after a renderer change
./scripts/regenerate-pixel-references.sh --measure-noise      # run-to-run noise floor per renderer

xcodegen generate                 # GLTFInspector.xcodeproj is gitignored
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -scheme GLTFInspector -destination 'platform=macOS' \
  -derivedDataPath /tmp/GLTFInspector-dd test
```

**Agents:** use `dev.sh install` / `dev.sh test` — never `open` or `build.sh` without
`--install-only` unless the user asked to launch. Debug logs: `.build/logs/debug.log` when
`GLTF_LOG_FILE` is set (dev.sh / launch.json).

`xcodebuild` alone writes `/tmp/GLTFInspector-<branch>-dd/…` — **not**
`/Applications/glTF Inspector.app`. Dock/Spotlight use `/Applications`; run `build.sh` to
install.

**Renderer regressions:** `GLTFInspectorTests/PixelDiffTests.swift` re-renders every pinned
Khronos sample (`TestModels/References/manifest.json`) through `WebRendererHost` *and* the
RealityKit `StillRenderer`, each against its own goldens in `TestModels/References/<renderer>/`.
That is the proof baseline for renderer refactors — `xcodebuild` cannot assert on a scene built
in JavaScript. The embedded validator runs over every fixture and sample (`GLTFValidatorCorpusTests`).
Comparison is perceptual (mean error *and* a bad-pixel count). Failures write
actual/expected/diff PNGs to `/tmp/GLTFInspector-pixel-diff/`. Missing fixtures **fail**
rather than skip. See [`TestModels/References/README.md`](TestModels/References/README.md).

Signing: `project.yml` (`DEVELOPMENT_TEAM`). Fixtures: `TestModels/Fixture Models/` via
`GLTFInspectorTests/TestFixtures.swift` (`#filePath`); regen `scripts/testdata/README.md`.

**Pipeline:** pixels → [`docs/pipeline-web-renderer.md`](docs/pipeline-web-renderer.md);
convert / inspector → [`docs/pipeline-gltf-to-realitykit.md`](docs/pipeline-gltf-to-realitykit.md);
why WebKit → [`docs/decision-web-renderer.md`](docs/decision-web-renderer.md).

## Worktrees & what ships

| Source | Treat as |
| --- | --- |
| `main` (merged commits) | Shipped behavior (RealityKit) |
| `.worktrees/` (gitignored) | Throwaway until merged — delete = gone |
| Dex / `.cursor/plans` | Intent only |

Before `git worktree remove`: `git log main..<branch>`, merge/cherry-pick. **Document window**
= host chrome + web canvas; **Quick Look** = web canvas, no convert. **`DESIGN.md`**: design
*principles* only — never paste shipped layout/state there. **`ShellRootView`**: fixed
`Theme.sidebarWidth` / `inspectorWidth` — not drag-resizable unless a task adds it.

## Pitfalls — do not repeat

**1. SwiftUI state in `init`** — dual spinners, 0 windows, `Modifying state during view update`.
Cause: touching `@Observable PreviewInteraction` from `View.init`. Rule: `init` assigns props /
`_State(initialValue:)` only; sync in `onAppear`/actions.

**2. Failed loads** — always `.failed(message)` on reject; never a spinner because
`sidebar == nil`. Host convert can still fail while the web canvas is already drawing.

**3. First paint** — Quick Look and the web canvas load the file in the page. Do not wait on
`EntityLoader` for pixels. The host still converts in parallel for chrome.

**4. One renderer, relative URLs** — do not add a second `viewer.html`. The Khronos renderer
rejects absolute library/LUT URLs; serve from the scheme-handler root. Load `libktx.js` and
the Draco wrapper as classic scripts *before* the module (`createKtxModule` /
`DracoDecoderModule`).

**5. Extension look + sandbox** — settings are shared only through the App Group
(`AppGroupSettings`: group suite + group container). Never read `UserDefaults.standard` or
Application Support for settings — in an appex that is its own container. Thumbnail/preview need
`com.apple.security.network.client` for WebKit XPC even with no network I/O. Reply with
`QLThumbnailReply(imageFileURL:)` — the CGContext drawing reply fails under Finder
(`QLThumbnailError 102`).

**6. Pixel-diff** — a missing pinned sample must **fail** coverage for both renderers, not skip
the harness. Regen uses the `TestModels/References/REGENERATE` sentinel
(`./scripts/regenerate-pixel-references.sh`), not env vars. Look at the PNGs before committing.

**7. Dual path gaps** — hide/solo still toggle the RK `Entity`; only selection is forwarded to
the page (`setSelectedNode`). Fit/export that read `PreviewInteraction` camera can disagree
with the web camera. `proof.sh` exercises RK `StillRenderer` on fixtures only; the per-sample
RK goldens are in the pixel-diff harness.

**8. RealityKit fallback only** (`PreviewScene` when `webCanvasURL` is nil)

- No `RealityViewCameraContent.entities` iteration in update — own `lookRoot`.
- `.realityViewCameraControls(.orbit)` + turntable `cameraTarget`.
- Clear IBL receivers before removing IBL entities.
- Scene refs in `@State` (`PreviewFrame`), not view `let`.

**9. Real-window verify** (unit tests won't catch **1**)

```bash
./scripts/build.sh
open -a "/Applications/glTF Inspector.app" /path/to/file.glb
log stream --style compact --info --predicate 'subsystem == "lol.mattias.gltf-inspector" OR (process == "glTF Inspector" AND composedMessage CONTAINS "Modifying state")'
# one "open start", one "open ready" (or "open failed"); Modifying state ≈ 0
```

**10. UI verification** — skill `macos-app-testing`. Non-intrusive by default: no focus steal,
Spaces switch, activate, pointer drive, or save/export sheets unless required.

1. Unit / pixel-diff (`xcodebuild test`) / `./scripts/proof.sh`
2. Peekaboo **background** (`see`, `window list`, background `click`); no
   `activate`/`frontmost`/osascript loops; classic capture (`PEEKABOO_CAPTURE_ENGINE=classic`)
3. Glass/layout clicks → Peekaboo once per frame change; warn before focus moves

No headless `--snapshot`/flatten-glass for PreviewUI. No screencapture-first. Never leave
Export/Save sheets open.
