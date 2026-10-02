# glTF Inspector

macOS 26+ Quick Look + Finder thumbnails for `.glb` / `.gltf`. Host **`GLTFInspector`** embeds
`PreviewExtension` and `ThumbnailExtension`. Two siloed renderers — the same one on the window,
Quick Look and Finder icons:

- **RealityKit** (`RendererRealityKit`, default, what `main` ships): `EntityLoader` convert feeds
  the canvas *and* RealityKit-only chrome. Window / Quick Look bind 1×1 `TextureResource`
  placeholders and replace after the first frame (`RealityCanvasView`); thumbnails and goldens
  stay eager.
- **WebKit** (`RendererWebKit` + `RendererWebKit/web-renderer/`): one `WKWebView` page (Khronos
  Sample Renderer) loads the file itself; panels come from JSON (`GLTFDocumentSummary`) — **no
  convert**.

**Renderer setting:** `settings.preview.renderer` = `realitykit` | `webkit` in the App Group
suite (`RendererKind`, default `realitykit`), **Settings ▸ Preview ▸ Renderer**. Only the host
can write the group (`defaults write` hits another domain). A change applies to new windows /
previews / icons. Debug: `-GLTFRenderer webkit|realitykit` (host only).

**New features, UX, or chrome:** [`DESIGN.md`](DESIGN.md) — principles, not layout (code wins).

## Layout

| Path | Role |
| --- | --- |
| `PreviewUI/` | Host chrome over seam protocols. **Do not import `GLTFCore` or a renderer.** DesignSystem wrappers only — no raw `Slider` / `Picker` / `glassEffect`. |
| `DesignSystem/` | Extension-safe tokens + Liquid Glass / controls. No GLTFCore / renderer imports. |
| `DesignCatalog/` | Showcase app (`./scripts/dev.sh catalog`). |
| `GLTFCore/` | File model, validator, stats, App Group settings + `AppLook`, HDRs, JSON panels, `RendererKind`. No RealityKit / WebKit / AppKit / PreviewUI. |
| `RendererRealityKit/` | Convert, `PreviewScene`, clips, stills, thumbnails. Only GLTFKit2 + DracoSwift target. Host adapters do not import RealityKit. |
| `RendererWebKit/` | `WebRendererHost`, `WebPreviewCanvas`. Page in `RendererWebKit/web-renderer/`. Only WebKit import. |
| `GLTFInspector/` | Neutral host (**imports neither renderer**): `DocumentShell`, `DocumentWindowModel`, `HostSidebarModel`, `FocusedPreviewCommands` (`GLTFInspector/PreviewFocus.swift`). |
| `GLTFInspector/Engine/` | `Engine*` adapters — seam mapping only. |
| `GLTFInspector/RendererRouter.swift` | Switch at open → `RealityDocumentWindow` / `WebDocumentWindow` (`#if canImport`). |
| `GLTFInspector/RealityKit/` | Convert → `RealityCanvasView` + chrome. |
| `GLTFInspector/WebKit/` | Page canvas + JSON panels. |
| `PreviewExtension/` / `ThumbnailExtension/` | Routers; RealityKit + WebKit file each. |
| `GLTFInspectorTests/` | Root never imports a renderer. Silos: `GLTFInspectorTests/RealityKit/`, `GLTFInspectorTests/WebKit/`. Goldens: `TestModels/References/`. |

Silos: [`docs/renderer-silos.md`](docs/renderer-silos.md). Convert:
[`docs/pipeline-gltf-to-realitykit.md`](docs/pipeline-gltf-to-realitykit.md). Pixels:
[`docs/pipeline-web-renderer.md`](docs/pipeline-web-renderer.md). Historical WebKit-only
decision: [`docs/decision-web-renderer.md`](docs/decision-web-renderer.md).

Ship **`GLTFInspector/`**. `main` is RealityKit-only; this branch is the two-renderer integration.

## Commands & build

```bash
./scripts/dev.sh install   # .build/ (+ /Applications on main); no open
./scripts/dev.sh test      # branch DerivedData; skips PerfBench
./scripts/dev.sh uitest    # opt-in; steals focus
./scripts/dev.sh bench     # opt-in PerfBench
./scripts/dev.sh run cube  # logs → .build/logs/debug.log
./scripts/dev.sh logs
./scripts/build.sh         # open /Applications + verify (main checkout only)
./scripts/build.sh --install-only
./scripts/verify.sh
./scripts/proof.sh         # StillRenderProofTests; --qlmanage optional
./scripts/release.sh
./scripts/fetch-test-models.sh
./scripts/regenerate-pixel-references.sh [webkit|realitykit]
```

**Agents:** `dev.sh install` / `dev.sh test` — never `open` or `build.sh` unless asked to launch.
`dev.sh` DerivedData: `/tmp/GLTFInspector-<branch-slug>-dd` (`scripts/lib/dev-env.sh`). Plain
`xcodebuild` uses Xcode's default DerivedData. Dock/Spotlight → `/Applications` via `build.sh`
(main only). Logs: `.build/logs/debug.log` when `GLTF_LOG_FILE` is set.

**Renderer regressions:** `PixelDiffWebKitTests` / `PixelDiffRealityKitTests` over
`TestModels/References/manifest.json`. Failures → `/tmp/GLTFInspector-pixel-diff/`. Missing
samples **fail**. [`TestModels/References/README.md`](TestModels/References/README.md).

Signing: `project.yml`. Fixtures: `TestModels/Fixture Models/` via
`GLTFInspectorTests/TestFixtures.swift`. Test GLBs: `GLTFInspectorTests/TestGLBFixtures.swift`
(`TestGLB`).

## Worktrees & what ships

| Source | Treat as |
| --- | --- |
| `main` (merged commits) | Shipped behavior (RealityKit) |
| git worktrees (gitignored) | Throwaway until merged |
| Dex / `.agents/plans` | Intent only |

Before `git worktree remove`: `git log main..<branch>`. **Document window** = host chrome + the
switched canvas; **Quick Look** / thumbnails follow the same switch (WebKit: no convert).
**`DESIGN.md`**: principles only — never paste shipped layout.

## Pitfalls — do not repeat

**1. SwiftUI state in `init`** — dual spinners, 0 windows, `Modifying state during view update`.
`init` assigns props / `_State(initialValue:)` only; sync in `onAppear`/actions.

**2. Failed loads** — always `.failed(message)`. Web canvas reports `WebCanvasController.phase`;
a convert failure only fails the panels, never a web canvas.

**3. First paint** — WebKit: page + JSON in parallel; canvas follows
`WebDocumentWindow.canvasState`; `WebCanvasController` outlives remount. RealityKit: canvas
follows convert (`RealityCanvasView`).

**4. One `viewer.html`** — serve from the scheme-handler root. Load `libktx.js` and the Draco
wrapper as classic scripts before the module.

**5. Extension sandbox** — settings only via App Group (`AppGroupSettings`). Never
`UserDefaults.standard` for settings. Appexes need `com.apple.security.network.client` for
WebKit XPC. Reply with `QLThumbnailReply(imageFileURL:)`.

**6. Pixel-diff** — missing sample **fails**. Regen: `REGENERATE` sentinel in
`TestModels/References/` (`./scripts/regenerate-pixel-references.sh`). Look at PNGs.

**7. Renderer gaps** — WebKit has no clip / morph / hide-solo / file-light chrome
(`WebPreviewCanvas.features`). Fit / reset / Export PNG → `FocusedPreviewCommands`. `proof.sh`
is RK fixtures; per-sample RK goldens are pixel-diff.

**8. RealityKit canvas** — skill `metal-realitykit-visionos` (`PreviewScene`: own `lookRoot`,
no `entities` iteration in update, clear IBL receivers first).

**9. Real-window verify** (unit tests miss **1**): `./scripts/build.sh` on main, then open
the `/Applications` app on a glb. Worktree: the `.build` app + `-GLTFRenderer webkit`.
One "open start", one "open ready" / "open failed"; no Modifying-state warnings.

**10. UI verification** — skill `macos-app-testing`. Peekaboo background; no focus steal /
`--snapshot` / leftover Export sheets.
