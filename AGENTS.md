# glTF Inspector

macOS 26+ Quick Look + Finder thumbnails for `.glb` / `.gltf`. Host **`GLTFInspector`** embeds
`PreviewExtension` and `ThumbnailExtension`. Every surface — window, Quick Look, Finder icon —
draws through one `WKWebView` page running the vendored Khronos glTF Sample Renderer
(`RendererWebKit/web-renderer/`). The page loads the file itself; panels come from the file's
JSON (`GLTFDocumentSummary`).

**New features, UX, or chrome:** [`DESIGN.md`](DESIGN.md) — principles, not layout (code wins).

## Layout

| Path | Role |
| --- | --- |
| `PreviewUI/` | Host chrome over seam protocols. **Do not import `GLTFCore` or `RendererWebKit`.** DesignSystem wrappers only — no raw `Slider` / `Picker` / `glassEffect`. |
| `DesignSystem/` | Extension-safe tokens + Liquid Glass / controls. No GLTFCore / renderer imports. |
| `DesignCatalog/` | Showcase app (`./scripts/dev.sh catalog`). |
| `GLTFCore/` | File model, validator, stats, App Group settings, Khronos HDRs, JSON panels. No WebKit / AppKit / PreviewUI. |
| `RendererWebKit/` | `WebRendererHost` (page host, scheme handler, bridge), `WebPreviewCanvas`, `WebCanvasController`. Page in `RendererWebKit/web-renderer/`. Only WebKit import. |
| `GLTFInspector/` | Host: `DocumentWindow` (window root), `DocumentShell`, `DocumentWindowModel`, `HostSidebarModel`, `FocusedPreviewCommands` (`PreviewFocus.swift`). |
| `GLTFInspector/Engine/` | `Engine*` adapters — seam mapping only. |
| `PreviewExtension/` / `ThumbnailExtension/` | Quick Look preview (`.live` page) / Finder thumbnail (`.still` page). |
| `GLTFInspectorTests/` | Unit + pixel-diff tests. Goldens: `TestModels/References/`. |

Pixels, bridge, failure: [`docs/pipeline-web-renderer.md`](docs/pipeline-web-renderer.md).

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
./scripts/release.sh
./scripts/fetch-test-models.sh
./scripts/regenerate-pixel-references.sh
```

**Agents:** `dev.sh install` / `dev.sh test` — never `open` or `build.sh` unless asked to launch.
`dev.sh` DerivedData: `/tmp/GLTFInspector-<branch-slug>-dd` (`scripts/lib/dev-env.sh`). Plain
`xcodebuild` uses Xcode's default DerivedData. Dock/Spotlight → `/Applications` via `build.sh`
(main only). Logs: `.build/logs/debug.log` when `GLTF_LOG_FILE` is set.

**Renderer regressions:** pixel-diff tests over `TestModels/References/manifest.json`. Failures →
`/tmp/GLTFInspector-pixel-diff/`. Missing samples **fail**.
[`TestModels/References/README.md`](TestModels/References/README.md).

Signing: `project.yml`. Fixtures: `TestModels/Fixture Models/` via
`GLTFInspectorTests/TestFixtures.swift`. Test GLBs: `GLTFInspectorTests/TestGLBFixtures.swift`
(`TestGLB`).

## Worktrees & what ships

| Source | Treat as |
| --- | --- |
| `main` (merged commits) | Shipped behavior |
| git worktrees (gitignored) | Throwaway until merged |
| Dex / `.agents/plans` | Intent only |

Before `git worktree remove`: `git log main..<branch>`. **`DESIGN.md`**: principles only — never
paste shipped layout.

## Pitfalls — do not repeat

**1. SwiftUI state in `init`** — dual spinners, 0 windows, `Modifying state during view update`.
`init` assigns props / `_State(initialValue:)` only; sync in `onAppear`/actions.

**2. Failed loads** — always `.failed(message)`. The canvas reports `WebCanvasController.phase`;
a JSON panel failure only fails the panels, never the canvas.

**3. First paint** — page + JSON load in parallel; the canvas follows
`DocumentWindow.canvasState`; `WebCanvasController` outlives the shell remount.

**4. One `viewer.html`** — serve from the scheme-handler root. Load `libktx.js` and the Draco
wrapper as classic scripts before the module.

**5. Extension sandbox** — settings only via App Group (`AppGroupSettings`). Never
`UserDefaults.standard` for settings; only the host can write the group (`defaults write` hits
another domain). Appexes need `com.apple.security.network.client` for WebKit XPC. Reply with
`QLThumbnailReply(imageFileURL:)`.

**6. Pixel-diff** — missing sample **fails**. Regen: `REGENERATE` sentinel in
`TestModels/References/` (`./scripts/regenerate-pixel-references.sh`). Look at PNGs.

**7. Chrome the page can't drive** — don't add it. Fit / reset / Export PNG →
`FocusedPreviewCommands`.

**8. Real-window verify** (unit tests miss **1**): `./scripts/build.sh` on main, then open
the `/Applications` app on a glb; in a worktree, the `.build` app. One "open start", one
"open ready" / "open failed"; no Modifying-state warnings.

**9. UI verification** — skill `macos-app-testing`. Peekaboo background; no focus steal /
`--snapshot` / leftover Export sheets.
