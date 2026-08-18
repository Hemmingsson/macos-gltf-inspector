# GLB Preview

macOS 15+ Quick Look + Finder thumbnails for `.glb` / `.gltf`. Host `GLBPreview` embeds `PreviewExtension` and `ThumbnailExtension`; shared code lives in `Shared/`.

## Commands

```bash
./scripts/verify.sh --build   # xcodegen + build + install to /Applications + README assets
./scripts/verify.sh           # check installed app + pluginkit
./scripts/publish.sh          # ICON.icon + promo → screenshots/
qlmanage -p path/to/file.glb  # preview proof
qlmanage -t path/to/file.glb  # thumbnail proof
```

Signing team: `project.yml` (`DEVELOPMENT_TEAM`). Proof is `qlmanage`, not a browser.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -scheme GLBPreview -destination 'platform=macOS' \
  -derivedDataPath /tmp/GLBPreview-dd test
```

## Do not

- Change `GLBPreviewCamera.makeTurntable`’s `(pivot, bounds)` return shape
- Set `content.environment` / `.skybox` in the preview (replaces the SwiftUI backdrop on macOS)
- Put studio/IBL entities under the turntable in preview (preview is unlit; thumbnails use `GLBPreviewLighting`)
- Spawn a `Task` per RealityView `update`
- Add load-path or per-frame logging — use `GLBLog.info` / `GLBLog.error` only
- Add outlier AABB / “robust” framing heuristics
- Add Spotlight importers or Finder Information metadata plugins
- Recreate `test-models/`, `Fixtures/`, `.build/`, `.cursor/`, `.dex/`, or `plans/`
