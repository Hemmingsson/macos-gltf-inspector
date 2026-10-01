# glTF Inspector (`webkit-renderer`)

macOS 26+ Quick Look + Finder thumbnails for `.glb` / `.gltf`. Host **`GLTFInspector`** embeds
`PreviewExtension` and `ThumbnailExtension`. Two siloed renderers draw the model — the same one in
the window, Quick Look and Finder icons:

- **RealityKit** (`RendererRealityKit`, default, what `main` ships): `EntityLoader` → GLTFKit2 →
  convert feeds the canvas *and* the RealityKit-only chrome (clips, morph sliders, hide/solo, debug
  modes, convert report).
- **WebKit** (`RendererWebKit` + `web-renderer/`): one `WKWebView` page running the Khronos glTF
  Sample Renderer, for closest-practical **1:1** with web glTF. The page loads the file itself; the
  panels come from the JSON alone (`GLTFDocumentSummary`) — **no convert runs**.

**Renderer setting:** `settings.preview.renderer` = `realitykit` | `webkit` in the App Group suite
(`RendererKind`, default `realitykit`), set in **Settings ▸ Preview ▸ Renderer** (lists only the
renderers linked into the build; the host is the only process that can write the group — a shell
`defaults write` lands in another domain). Window, Quick Look and thumbnail read it when
they open a file, so a change applies to new windows / previews / icons; open windows keep theirs.
Debug builds also take `-GLTFRenderer webkit|realitykit` (launch-argument override, host only).

**New features, UX, or chrome:** read [`DESIGN.md`](DESIGN.md) first — product principles, not
layout spec (code wins on what ships where).

## Layout

| Path | Role |
| --- | --- |
| `PreviewUI/` | Host chrome over seam protocols. **Do not import `GLTFCore` or a renderer framework.** Feature code uses DesignSystem wrappers — no raw `Slider` / `Picker` / `glassEffect` / `GlassEffectContainer` / `Color(red:`. |
| `DesignSystem/` | Extension-safe framework: `DS` tokens (color, spacing, metrics, motion, `DS.Shortcuts`) and the Liquid Glass / control components. Linked by `PreviewUI`, `RendererRealityKit` (Quick Look chrome) and the host (embedded once). No GLTFCore / renderer imports. |
| `DesignCatalog/` | Showcase app for tokens, DS components and PreviewUI composites (`./scripts/dev.sh catalog`). |
| `GLTFCore/` | Extension-safe framework: glTF file model (JSON document, GLB read side), validator, stats, App Group settings + `AppLook`, bundled Khronos HDRs (`KhronosEnvironments.bundledDirectory`), PNG writer, JSON model bounds (`ModelBounds`), the JSON-only panel summary (`GLTFDocumentSummary`, `ViewModeAvailability`), the renderer switch (`RendererKind`), neutral render values (`RenderLook`, `RenderViewMode`, `CameraPreset`, `RendererFeature`; host maps PreviewUI ↔ core in `Engine/EngineCoreMapping.swift`). No RealityKit / WebKit / AppKit / PreviewUI. Embedded once in the host; the extensions link it. |
| `RendererRealityKit/` | Extension-safe RealityKit renderer framework over `GLTFCore`: `EntityLoader` (no file rewrite: GLTFKit2 parses the file as authored), `SpecGlossBake`, `Convert/`, `RealityLook` (the one `RenderLook` → RealityKit mapping) and `RealityPolicy` (reported non-spec rules), `RealityPreviewCanvas` (`PreviewScene` + Quick Look chrome), camera / lighting / floor / selection visuals, clips (`RealityClipPlayer`), morphs, debug modes, `StillRenderer` / `LiveStillRequest` (returns a `CGImage`; the host owns the save panel). Also `PreviewHostingView` / `PreviewEventView` (`PreviewInteraction` scroll/magnify/drag plumbing, generic over the root view) for the RealityKit adapters, and `RealityThumbnail` (Finder icon). Only target linking GLTFKit2 + DracoSwift; `GLBTry.h` is a public header (no bridging header), `GLBDracoDecompressor` is found by class name. Host code talks to it through neutral entry points (`LoadedModel` helpers, `PreviewOverlay` values, `PreviewDebugMode.renderViewMode`) and does not import RealityKit. Embedded once in the host; both extensions link it. |
| `RendererWebKit/` | Extension-safe WebKit renderer framework over `GLTFCore`: `WebRendererHost` (one `WKWebView`, `.live` / `.still`; `callAsyncJavaScript` on five page functions — open / apply / camera / still / stats — each call with its own timeout), scheme handler, `WebPreviewCanvas` + `Look` (`RenderLook` + view state, mapped to page values once in `WebRendererLook.swift`), load copy, `CachedQuickLookThumbnail`. Public API is only what host/appexes call (`WebRendererHost` start / load / apply / renderStill / renderStillPNG / isBroken, `WebPreviewCanvas.Look` + `Look.stored()`, `WebRendererError`, `WebPreviewCanvas(url:look:placeholderImage:host:controller:)`, `WebCanvasController` (phase ending in `.failed`, fit / reset / apply(preset:) / snapshot, survives a remount), `WebRendererMode`, `CachedQuickLookThumbnail.existingIcon`); tests use `@testable`. The only module that imports WebKit. Embedded once in the host; both extensions link it. |
| `RendererWebKit/web-renderer/` | The one `viewer.html` + Khronos bundle, pinned in `VERSION` with `THIRD_PARTY_NOTICES.txt` (`scripts/vendor-web-renderer.sh`). Ships once, inside `RendererWebKit.framework`, found via `Bundle(for:)` (in an appex `Bundle.main` is the appex). HDRs stay in `GLTFCore`. Do not fork a second page. |
| `GLTFInspector/` (generic) | Renderer-neutral host: **imports neither renderer**. `DocumentShell` (PreviewUI `ShellRootView` + adapters around one canvas), `DocumentWindowModel` (per-window sidebar, settings, viewport, open / validation lifecycle, `openSummary` for JSON-only panels), `PreviewSession`, `HostSidebarModel`, `PreviewFocus` (`FocusedPreviewCommands`: fit / preset / reset / screenshot → `CGImage`, registered by the mounted canvas, forwarded by `EngineViewportController`). |
| `GLTFInspector/Engine/` | `Engine*` adapters — seam mapping only; no PreviewUI rewrites. `RendererAvailability` narrows `DerivedAvailability` to the renderer's `features`. `ScreenshotCameraPose` owns the PNG save panel. |
| `GLTFInspector/RendererRouter.swift` | The host's one renderer spot: `DocumentWindowRouter` reads the switch at open and mounts `RealityDocumentWindow` or `WebDocumentWindow`; each case is `#if canImport(<Renderer>)`. |
| `GLTFInspector/RealityKit/` | RealityKit adapter: `RealityDocumentWindow` (convert → canvas + chrome, scene/variant reload, morphs), `PreviewView` + `HostPreviewContainer` (`RealityPreviewCanvas` in `PreviewHostingView`, mounted once convert lands), playback controller, and `+RealityKit` extensions (`EngineSceneModel(loaded:)`, `PreviewSession.bindings`, `HostSidebarModel: PreviewOverlay`, the offscreen PNG re-render). |
| `GLTFInspector/WebKit/` | WebKit adapter: `WebDocumentWindow` (page canvas + JSON panels, `canvasState`), `WebPreviewCanvas.Look` mapping, `FocusedPreviewCommands.web`. |
| `PreviewExtension/` | Quick Look. `PreviewViewController` is the router (reads the switch, embeds a child controller); `QuickLookRealityKit.swift` (convert + `RealityPreviewCanvas` with its inline chrome, as `main`) and `QuickLookWebKit.swift` (prestarted page, no convert). Links `GLTFCore` + both renderers. |
| `ThumbnailExtension/` | `ThumbnailProvider` is the router; `ThumbnailRealityKit.swift` (`RealityThumbnail` → `StillRenderer`, as `main`) and `ThumbnailWebKit.swift` (warm `WebRendererHost(.still)`). Links `GLTFCore` + both renderers. |
| `GLTFInspectorTests/` (root) | Renderer-neutral tests: import `GLTFCore` / the host / `PreviewUI`, **never a renderer**. Includes the pixel-diff core (`PixelDiff` comparator, `PixelDiffManifest`, `PixelDiffRun` loops), GLB byte builders (`TestGLBFixtures.swift`, `TestGLB` writer) and document / bounds / stats tests that read the JSON directly. One test target for everything. |
| `GLTFInspectorTests/RealityKit/` | Tests of the RK renderer and RK-backed host code (`@testable import RendererRealityKit`): convert, entity helpers (`RealityTestHelpers.swift`), overlay / selection, `PixelDiffRealityKitTests` (+ its generator). |
| `GLTFInspectorTests/WebKit/` | Tests of the web renderer (`@testable import RendererWebKit`): `PixelDiffWebKitTests` (+ the generator that records the manifest poses). |
| `TestModels/References/` | Pinned sample manifest + per-renderer pixel-diff goldens (`webkit/`, `realitykit/`). |

**Removing a renderer** (e.g. once one ships): delete its framework dir + target in `project.yml`
(and its lines in the host / extension / test `dependencies:`), its adapter files
(`GLTFInspector/<Renderer>/`, `PreviewExtension/QuickLook<Renderer>.swift`,
`ThumbnailExtension/Thumbnail<Renderer>.swift`) and `GLTFInspectorTests/<Renderer>/`. Nothing
else needs an edit: the router files and `GLTFInspectorTests/CrossRenderer/` are
`#if canImport(Renderer…)`, and root tests import no renderer. Optionally drop
`TestModels/References/<renderer>/` and its manifest tolerance (nothing checks them any more).
Build clean (a fresh DerivedData): a stale framework module in `Build/Products` would keep
`canImport` true. Proven on this branch: no-RealityKit and no-WebKit silos both pass
`dev.sh test`. **Adding** code: only the adapter folders,
the router files, `GLTFInspectorTests/<Renderer>/` and (gated) `GLTFInspectorTests/CrossRenderer/`
may `import RendererRealityKit` / `RendererWebKit`; each framework exposes `static let features: Set<RendererFeature>` on its canvas,
and host chrome it cannot drive is hidden through `RendererAvailability` / `canHideNodes`, not `if`s.

Ship **`GLTFInspector/`** — not legacy `GLBPreview/`. Product on **`main`** is still RealityKit;
this worktree is throwaway until merged.

## Commands & build

```bash
./scripts/dev.sh install          # worktree-aware → .build/ (+ /Applications on main); no open; keeps the signed test bundle in PlugIns/ after a test run
./scripts/dev.sh test             # xcodegen + xcodebuild test into this branch's DerivedData (args → xcodebuild); leaves out PerfBench
./scripts/dev.sh bench            # opt-in perf bench (PerfBench, GLTF_BENCH=1, GLTF_BENCH_RUNS=3) → table + .build/bench/<stamp>.txt
./scripts/dev.sh run cube         # install + launch fixture; logs → .build/logs/debug.log
./scripts/dev.sh logs             # tail debug log (agents: read .build/logs/debug.log)
./scripts/build.sh                # install + open /Applications + verify (ship check; main checkout only)
./scripts/build.sh --install-only # same as dev.sh install (VS Code Build task)
./scripts/verify.sh               # installed app + pluginkit
./scripts/proof.sh                # StillRenderProofTests (RK convert still); --qlmanage adds a timed qlmanage
./scripts/tidy-metrics.sh [label] [tests]  # periphery + swiftlint + jscpd + LOC → .agents/research/tidy-baseline/<label>/, delta vs summary-0
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

**Renderer regressions:** `PixelDiffWebKitTests` / `PixelDiffRealityKitTests` (in the renderer
test folders, over the neutral `GLTFInspectorTests/PixelDiff*.swift` core) re-render every pinned
Khronos sample (`TestModels/References/manifest.json`) through `WebRendererHost` and the
RealityKit `StillRenderer`, each against its own goldens in `TestModels/References/<renderer>/`.
That is the proof baseline for renderer refactors — `xcodebuild` cannot assert on a scene built
in JavaScript. The embedded validator runs over every fixture and sample (`GLTFValidatorCorpusTests`).
Comparison is perceptual (mean error *and* a bad-pixel count). Failures write
actual/expected/diff PNGs to `/tmp/GLTFInspector-pixel-diff/`. Missing fixtures **fail**
rather than skip. See [`TestModels/References/README.md`](TestModels/References/README.md).

Signing: `project.yml` (`DEVELOPMENT_TEAM`). Fixtures: `TestModels/Fixture Models/` via
`GLTFInspectorTests/TestFixtures.swift` (`#filePath`); regen `scripts/testdata/README.md`.

**RealityKit convert notes** (detail in [`docs/pipeline-gltf-to-realitykit.md`](docs/pipeline-gltf-to-realitykit.md)):
no temp GLB / prepare pass — WebP, quantization, meshopt, KTX2, Draco and unnamed nodes are
GLTFKit2's; spec-gloss is baked in place on the parsed asset; instancing is one child entity per
instance. Kept for measured wins: packed SIMD accessors, the `LowLevelMesh` float3 path (now any
static accessor, tight ones `memcpy`'d), material identity cache, skeletal densify ≤ 30 fps,
cutout-as-mask BLEND (a `RealityPolicy` rule), 1024 px texture cap on Finder icons only.
Texture channels are `Texture.swizzle` on one `.raw` upload; `KHR_texture_transform` / `texCoord`
are material parameters (`TextureTransforms`), never baked into UVs. Clips build in their own
`GLBTry`; `build` returns `BuildResult` (no static problem state). Look constants (yaw π − Y,
lights × 591, spot × π and 2× cone) live only in `RealityLook`. No CreateOptions / mip / Metal-upload
/ off-main-decode re-bench without a new asset class (EXP ledger; off-main decode measured flat in
seam 11). Test GLBs are written with the test-side `TestGLB`, not a renderer API.

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
= host chrome + the switched renderer's canvas; **Quick Look** / thumbnails follow the same switch
(WebKit: no convert; Quick Look = minimal chrome). **`DESIGN.md`**: design *principles* only —
never paste shipped layout/state there (use code/tests/`AGENTS.md`). **`ShellRootView`**:
`NavigationSplitView` + selection-driven `.inspector`; column widths from `DS.Metrics` (sidebar
220…520, inspector 260…560). **Canvas** is full-bleed (`.ignoresSafeArea()`, no `.clipped()`)
under the floating panes; overlay clusters stay in the leading/trailing safe area.

## Pitfalls — do not repeat

**1. SwiftUI state in `init`** — dual spinners, 0 windows, `Modifying state during view update`.
Cause: touching `@Observable PreviewInteraction` from `View.init`. Rule: `init` assigns props /
`_State(initialValue:)` only; sync in `onAppear`/actions.

**2. Failed loads** — always `.failed(message)` on reject; never a spinner because
`sidebar == nil`. The web canvas reports its own failure (`WebCanvasController.phase`);
a convert failure only fails the panels, never a web canvas that draws.

**3. First paint** — on WebKit, Quick Look and the web canvas load the file in the page; the window's
panels read the JSON in parallel (no `EntityLoader`). The canvas region follows the page
(`WebDocumentWindow.canvasState` → `ShellRootView(canvasState:)`), and the window's
`WebCanvasController` outlives `.id(window.mountID)` so the remount adopts the running page. On
RealityKit the canvas follows convert.

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

**7. Renderer gaps** — the page has no clip playback, morph weights, hide/solo, skeleton overlay or
file-light toggle (`WebPreviewCanvas.features`); that chrome is absent in WebKit windows. Selection
is forwarded to the page (`Look.selectedNodeIndex`). Fit / presets / reset / Export PNG act on the mounted
canvas (`FocusedPreviewCommands`). `proof.sh` exercises RK `StillRenderer` on fixtures only; the per-sample
RK goldens are in the pixel-diff harness.

**8. RealityKit canvas** (`PreviewScene`)

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
# per renderer, Debug .build app: open -n -g -a "<.build app>" --args -GLTFRenderer webkit <file>
```

**10. UI verification** — skill `macos-app-testing`. Non-intrusive by default: no focus steal,
Spaces switch, activate, pointer drive, or save/export sheets unless required.

1. Unit / pixel-diff (`xcodebuild test`) / `./scripts/proof.sh`
2. Peekaboo **background** (`see`, `window list`, background `click`); no
   `activate`/`frontmost`/osascript loops; classic capture (`PEEKABOO_CAPTURE_ENGINE=classic`)
3. Glass/layout clicks → Peekaboo once per frame change; warn before focus moves

No headless `--snapshot`/flatten-glass for PreviewUI. No screencapture-first. Never leave
Export/Save sheets open.
