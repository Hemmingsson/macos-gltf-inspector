# GLB Preview

macOS 26+ Quick Look + Finder thumbnails for `.glb` / `.gltf`. Host `GLBPreview` embeds `PreviewExtension` and `ThumbnailExtension`. Convert/render live in `Shared/` (+ `Shared/Convert/`); host outliner and settings live in `GLBPreview/`.

## Goal

Closest practical **1:1** glTF rendering via **native RealityKit** on Mac. Prefer fidelity and simplicity over product overhead. Target: **latest macOS** on **Apple Silicon**.

## Commands

```bash
./scripts/build.sh            # xcodegen + Debug build + install to /Applications
./scripts/verify.sh           # check installed app + pluginkit
./scripts/proof.sh            # StillRenderProofTests (+ optional qlmanage)
./scripts/release.sh          # Developer ID + notary + Sparkle appcast + gh release
./scripts/vendor-khronos-environments.sh  # refresh bundled IBL HDRs
```

Signing team: `project.yml` (`DEVELOPMENT_TEAM`). Primary proof is still PNG via `StillRenderProofTests`.

```bash
xcodegen generate   # required: GLBPreview.xcodeproj is gitignored
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -scheme GLBPreview -destination 'platform=macOS' \
  -derivedDataPath /tmp/GLBPreview-dd test
```

Load-time work already shipped (−54% vs an old baseline on a frozen corpus). Champion ideas kept in code: cutout-as-mask BLEND, packed SIMD/`float3` meshes, material identity cache, skeletal densify ≤30 fps. Do not re-bench CreateOptions/mip/Metal-upload folklore without new measured evidence naming which assets move; residual wall is RealityKit `TextureResource.generate` on large rasters.

## Pitfalls — do not repeat

### 1. Never mutate `@Observable` / `@State` in `View.init` or RealityView `make`/`update`

**Symptom:** Eternal dual spinners / 0 windows; `Modifying state during view update`.

**Cause:** Touching `@Observable PreviewInteraction` from `View.init` re-enters SwiftUI.

**Rule:** `View.init` only assigns stored props / `_State(initialValue:)`. Floor/orbit sync in `onAppear` or actions. RealityView `make`/`update`: wrap state writes in `Task { @MainActor in … }`.

### 2. Failed loads must show copy, not a spinner

Sidebar spinner whenever `sidebar == nil` hid `.failed`. Always set `.failed(message)` when a URL is rejected.

### 3. Don’t block first paint on IBL

Open path is model only (`EntityLoader.load` → `.ready` / `.failed`). Prefetch HDR in `PreviewScene`; temporary key+fill until the probe is ready.

### 4. RealityKit crash landmines

- Do not iterate `RealityViewCameraContent.entities` during update. Own a `lookRoot`.
- Prefer `.realityViewCameraControls(.orbit)` + turntable pivot as `cameraTarget`.
- `PreviewCamera.applyView` is one-shot fit/light posing only (not interactive scroll).
- Floor toggle is visual only; must not change camera limits.
- Scroll/pinch is infinite dolly along look; Shift-drag pans camera + pivot (swallow so `.orbit` does not also run).
- Auto-rotate yaws a spin child under the turntable; keep `cameraTarget` on the pivot.
- Clear IBL receivers before removing IBL light entities.
- Persist scene entity refs in `@State` (`PreviewFrame`), not a plain `let` on the view struct.

### 5. Verify with a real window

```bash
./scripts/build.sh
open -a /Applications/GLBPreview.app /path/to/file.glb
log stream --style compact --info --predicate 'subsystem == "com.laurie.GLBPreview" OR (process == "GLBPreview" AND composedMessage CONTAINS "Modifying state")'
# Expect: one "open start", one "open ready" (or "open failed"); Modifying state ≈ 0.
```

Unit tests alone will not catch (1).
