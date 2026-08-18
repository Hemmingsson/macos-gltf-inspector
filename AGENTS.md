# GLB Preview

macOS Quick Look + Finder thumbnails for `.glb` / `.gltf`. Host app `GLBPreview` embeds `PreviewExtension` and `ThumbnailExtension`. Both share `Shared/`.

## Build and install

```bash
brew install xcodegen
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
 xcodebuild -scheme GLBPreview -destination 'platform=macOS' \
 -derivedDataPath /tmp/GLBPreview-dd build

rm -rf /Applications/GLBPreview.app
cp -R /tmp/GLBPreview-dd/Build/Products/Debug/GLBPreview.app /Applications/
qlmanage -r
open /Applications/GLBPreview.app
```

Signing team is in `project.yml` (`DEVELOPMENT_TEAM`). No unit-test target. Proof is Quick Look, not a browser.

```bash
./scripts/verify.sh # /Applications/GLBPreview.app + pluginkit
./scripts/verify.sh --build # generate + build + install + README GIF
./scripts/promo-gif.sh # offscreen 360° GIF, no host window
qlmanage -p path/to/file.glb
qlmanage -t path/to/file.glb
log stream --style compact --info --predicate 'subsystem == "com.laurie.GLBPreview"'
```

Use `GLBLog.info` / `GLBLog.error` only. Do not add load-path or per-frame logging.

## Architecture

| Piece | Role |
| --- | --- |
| `GLBEntityLoader` | Draco hook, spec/gloss rewrite, `GLTFAsset` off the main actor, `GLTFRealityKitLoader.convert` on the main actor |
| `GLBMetalRoughPrepare` | Peeks the GLB JSON chunk first; only reads the full file when conversion is needed |
| `GLBPreviewCamera.makeTurntable` | Returns `(pivot, bounds)` — do not change that shape (`ThumbnailProvider` unpacks it) |
| `GLBPreviewLighting` | Shared gray `EnvironmentResource` + key 2500 |
| `GLBPreviewView` | `RealityView` preview (excluded from the thumbnail and promo targets) |
| `GLBPreviewStats` | JSON-only mesh/material/animation/node/texture counts + duration for the in-viewer overlay |
| `GLBStillRenderer` | Offscreen `RealityRenderer` frames (Finder icons + README GIF) |
| `ThumbnailProvider` | `RealityRenderer` still life |
| `GLBPromo` | Windowless CLI: 360° PNG frames → `scripts/promo-gif.sh` → GIF |

Preview IBL: top-level `iblLight` sibling of the turntable, `ImageBasedLightComponent(source: .single(resource), intensityExponent: 0)`, receivers on every `ModelComponent` under the turntable. Load the probe once (`.task`); attach synchronously in `update` when the resource exists. Never `Task` inside RealityView `update` (it runs every frame). After lights-off, in-flight IBL work must no-op.

Thumbnails set `renderer.lighting.resource` to the same probe. Do not set `content.environment = .skybox` in the preview — on macOS that replaces the SwiftUI backdrop.

## Framing

Front 3/4, Y-up, camera on −Z. `thinAxis`: min/max extent ratio `< 0.02`. Thin X/Z (standing cards): face-on yaw, `autoRotate` starts false. Thin Y (manholes): keep 3/4 and allow spin.

Do not add “robust” / outlier AABB clustering. On the 50-model set it “fixes” specks (Mighty, Billiard, S_t_happens) by also reframing known-good packs (lilac `Plane_Filler`).

`fitDistance` treats aspect outside `(0.05, 20)` as 1 — `RealityView.make` often runs before layout.

## Do not

- Change `makeTurntable`’s return type
- Put `iblLight` under the turntable (`syncStudioLights` only sees `content.entities` by name)
- Re-enable verbose file/`print` logging on the hot path
- Recreate `test-models/`, `Fixtures/`, `.build/`, `.cursor/`, `.dex/`, or `plans/`
- Verify preview in a browser — use `qlmanage` only
- Add Spotlight importers or Finder Information metadata plugins
