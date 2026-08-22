# glTF Inspector

macOS 26+ Quick Look + Finder thumbnails for `.glb` / `.gltf`. Host **`GLTFInspector`** embeds `PreviewExtension` and `ThumbnailExtension`; convert/render in `Shared/` (+ `Shared/Convert/`). Goal: closest practical **1:1** glTF via native RealityKit — fidelity over product overhead; **latest macOS**, **Apple Silicon**.

**New features, UX, or chrome:** read [`DESIGN.md`](DESIGN.md) first — product principles, not layout spec (code wins on what ships where).

## Layout

| Path | Role |
| --- | --- |
| `PreviewUI/` | Host chrome over seam protocols. **Do not import `Shared/`.** |
| `GLTFInspector/Engine/` | `Engine*` adapters — seam mapping only; no PreviewUI rewrites. |
| `GLTFInspector/HostShellRootView.swift` | Document window: `ShellRootView` + adapters + `PreviewView` canvas. |
| `GLTFInspector/HostSidebarModel.swift` | Selection, re-convert, visibility — behind `EngineSelectionModel`. |
| `Shared/PreviewScene.swift` | RealityView host. Host-bare with sidebar (`showsInlineChrome == false`); QL uses `PreviewQuickLookChrome.swift`. |
| `Shared/PreviewChrome.swift` | Interaction + hosting shared by host and QL. |

Ship **`GLTFInspector/`** — not legacy `GLBPreview/`. Product code on **`main`** at repo root.

## Commands & build

```bash
./scripts/build.sh              # xcodegen + Debug + install /Applications + verify
./scripts/build.sh --install-only   # build + copy; no open/verify (VS Code Run preLaunchTask)
./scripts/verify.sh             # installed app + pluginkit
./scripts/proof.sh              # StillRenderProofTests (+ optional qlmanage)
./scripts/release.sh            # Developer ID + notary + Sparkle + gh release
./scripts/vendor-khronos-environments.sh
./scripts/fetch-test-models.sh  # optional Khronos GLBs → TestModels/Khronos samples (gitignored)

xcodegen generate               # GLTFInspector.xcodeproj is gitignored
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -scheme GLTFInspector -destination 'platform=macOS' \
  -derivedDataPath /tmp/GLTFInspector-dd test
```

`xcodebuild` alone writes `/tmp/GLTFInspector-dd/…` — **not** `/Applications/glTF Inspector.app`. Dock/Spotlight use `/Applications`; run `build.sh` to install.

Signing: `project.yml` (`DEVELOPMENT_TEAM`). Primary proof: PNG via `StillRenderProofTests`. Fixtures: `TestModels/Fixture Models/` via `GLTFInspectorTests/TestFixtures.swift` (`#filePath`); regen `scripts/testdata/README.md`.

Champion convert (in code): cutout-as-mask BLEND, packed SIMD/`float3` meshes, material identity cache, skeletal densify ≤30 fps. No CreateOptions/mip/Metal-upload re-bench without measured asset wins; residual wall is `TextureResource.generate` on large rasters. **Pipeline detail:** [`docs/pipeline-gltf-to-realitykit.md`](docs/pipeline-gltf-to-realitykit.md).

## Worktrees & what ships

| Source | Treat as |
| --- | --- |
| `main` (merged commits) | Shipped behavior |
| `.worktrees/` (gitignored) | Throwaway until merged — delete = gone |
| Dex / `.cursor/plans` | Intent only |

Before `git worktree remove`: `git log main..<branch>`, merge/cherry-pick. **Document window** = host chrome + canvas; **Quick Look** = minimal chrome. **`DESIGN.md`**: design *principles* only — never paste shipped layout/state there (use code/tests/`AGENTS.md`). **`ShellRootView`**: fixed `Theme.sidebarWidth` / `inspectorWidth` — not drag-resizable unless a task adds it.

## Pitfalls — do not repeat

**1. SwiftUI state in `init` / RealityView `make`/`update`** — dual spinners, 0 windows, `Modifying state during view update`. Cause: touching `@Observable PreviewInteraction` from `View.init`. Rule: `init` assigns props / `_State(initialValue:)` only; sync in `onAppear`/actions; RealityView writes in `Task { @MainActor in … }`.

**2. Failed loads** — always `.failed(message)` on reject; never a spinner because `sidebar == nil`.

**3. First paint** — open path is model only (`EntityLoader.load` → `.ready`/`.failed`); prefetch IBL in `PreviewScene`; temp key+fill until probe ready.

**4. RealityKit landmines**

- No `RealityViewCameraContent.entities` iteration in update — own `lookRoot`.
- `.realityViewCameraControls(.orbit)` + turntable `cameraTarget`.
- `PreviewCamera.applyView`: one-shot fit/light only (not scroll).
- Floor toggle: visual only; no camera limit changes.
- Scroll/pinch: infinite dolly; Shift-drag pans camera+pivot (swallow so `.orbit` doesn't double).
- Auto-rotate: yaw spin child; keep `cameraTarget` on pivot.
- Clear IBL receivers before removing IBL entities.
- Scene refs in `@State` (`PreviewFrame`), not view `let`.

**5. Real-window verify** (unit tests won't catch **1**)

```bash
./scripts/build.sh
open -a "/Applications/glTF Inspector.app" /path/to/file.glb
log stream --style compact --info --predicate 'subsystem == "lol.mattias.gltf-inspector" OR (process == "glTF Inspector" AND composedMessage CONTAINS "Modifying state")'
# one "open start", one "open ready" (or "open failed"); Modifying state ≈ 0
```

**6. UI verification** — skill `macos-app-testing`. Non-intrusive by default: no focus steal, Spaces switch, activate, pointer drive, or save/export sheets unless required.

1. Unit / `./scripts/proof.sh`
2. Peekaboo **background** (`see`, `window list`, background `click`); no `activate`/`frontmost`/osascript loops; classic capture (`PEEKABOO_CAPTURE_ENGINE=classic`) — not ScreenCaptureKit via Claude.app
3. Glass/layout clicks → Peekaboo once per frame change; warn before focus moves

No headless `--snapshot`/flatten-glass for PreviewUI. No screencapture-first. Never leave Export/Save sheets open.
