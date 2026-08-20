# GLB Preview

macOS 26+ Quick Look + Finder thumbnails for `.glb` / `.gltf`. Host `GLBPreview` embeds `PreviewExtension` and `ThumbnailExtension`. Convert/render live in `Shared/` (+ `Shared/Convert/`); host outliner and settings live in `GLBPreview/`.

## Goal

Closest practical **1:1** glTF rendering via **native RealityKit** on Mac. Prefer fidelity and simplicity over product overhead, abstraction layers, or “super secure” hardening. Target: **latest macOS** on an **Apple Silicon MacBook (M2)**.

## Commands

```bash
./scripts/build.sh            # xcodegen + Debug build + install to /Applications
./scripts/verify.sh           # check installed app + pluginkit
./scripts/proof.sh            # StillRenderProofTests (+ optional qlmanage)
./scripts/release.sh          # Developer ID + notary + Sparkle appcast + gh release
./scripts/vendor-khronos-environments.sh  # refresh bundled IBL HDRs
LABEL=<id> ./scripts/load-bench.sh        # frozen 10-GLB load+still timing
cd ReadmePreviews && npm i && npm start   # README spinning-model WebPs → assets/
```

Signing team: `project.yml` (`DEVELOPMENT_TEAM`). Primary proof is still PNG via `StillRenderProofTests`; `qlmanage` is optional in `proof.sh`.

```bash
xcodegen generate   # required: GLBPreview.xcodeproj is gitignored
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -scheme GLBPreview -destination 'platform=macOS' \
  -derivedDataPath /tmp/GLBPreview-dd test
```

## Load-time experiments

Campaign closed (cp-003, −54% vs baseline-v2): `experiments/PERFORMANCE-OPTIMIZATION.md`. Ledger: `experiments/` (`PROTOCOL.md`, `results.json`, `WHAT-WE-TRIED.md`, `residual-map.json`). Bench: `LABEL=<id> ./scripts/load-bench.sh`.

## Pitfalls we hit (2026-08-20) — do not repeat

### 1. Never mutate `@Observable` / `@State` in `View.init` or RealityView `make`/`update`

**Symptom:** Eternal dual spinners, sometimes **0 windows**, no “failed to load” UI. Console floods `Modifying state during view update` and (was) `autoRotate disabled for standing plane` every frame.

**Cause:** `PreviewScene.init` called `interaction.setFloorOn(...)`. View structs are re-created during body updates; touching `@Observable PreviewInteraction` re-entered SwiftUI → infinite loop. Load Tasks never settled on `.ready`/`.failed`, so the sidebar kept showing `ProgressView`.

**Rule:**
- `View.init`: only assign stored props / `_State(initialValue:)`. No `interaction.*`, no logging that implies side effects you care about per-init.
- Floor / orbit sync: `onAppear` / explicit actions (`setShowFloor`).
- RealityView `make`/`update`: do not write `@State` or `@Observable` inline — `Task { @MainActor in … }` (see orbit fit + clip start).

### 2. “No error” ≠ success

Host sidebar showed a spinner whenever `sidebar == nil`, including `.failed`. A hang on `.loading` looked identical to a soft failure.

**Rule:** Failed loads must show copy in the sidebar (and detail), not another spinner. Don’t `return` from `loadDocument` without setting `.failed` when the URL is rejected.

### 3. Don’t block first paint on IBL

Open path is **model only** (`EntityLoader.load` → `.ready` / `.failed(message)`). Never await HDR/`EnvironmentResource` before showing the mesh.

**Rule:** `PreviewView.State.loaded` must not touch lighting. `PreviewScene` calls `prefetchLook` on appear / look change and reapplies when the probe is ready. Until then, temporary key+fill so the model isn’t black.

Failed opens must show the error string in the sidebar and detail — never another spinner.

### 4. RealityKit crash landmines (still true)

- Do **not** iterate `RealityViewCameraContent.entities` during update (`EXC_BREAKPOINT`). Own a `lookRoot` entity; put lights under it.
- Prefer RealityKit `.realityViewCameraControls(.orbit)` + turntable pivot as `cameraTarget` (real mesh bounds — an empty focus entity nose-dives framing).
- `PreviewOrbit.applyView` is only for one-shot fit/light poses (not interactive scroll).
- Floor toggle is visual only; it must not change camera limits.
- Scroll/pinch is **infinite** position dolly along the camera look axis. Shift-drag pans camera + pivot together (sticky until mouse-up); swallow those events so `.orbit` does not also run.
- Auto-rotate yaws a spin child under the turntable; keep `cameraTarget` on the pivot.
- Clear IBL **receivers before** removing IBL light entities.
- Persist scene entity refs in `@State` (`PreviewFrame`), not a plain `let` on the view struct (parent `updateNSView` recreates the struct).

### 5. Tab / windowbar chrome

`toggleTabBar` + KVO can re-enter chrome sync. Guard nested `sync`, and only `presentDocument` once per `NSWindow`. Don’t debug “load hung” as tabs until you’ve ruled out (1).

### 6. How to verify next time

```bash
./scripts/build.sh
open -a /Applications/GLBPreview.app /path/to/file.glb
log stream --style compact --info --predicate 'subsystem == "com.laurie.GLBPreview" OR (process == "GLBPreview" AND composedMessage CONTAINS "Modifying state")'
# Expect: one "open start", one "open ready" (or "open failed"); Modifying state ≈ 0; no autoRotate spam.
```

Unit tests alone will **not** catch (1) — it needs a real document window + RealityView.
