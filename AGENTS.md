# GLB Preview

macOS 15+ Quick Look + Finder thumbnails for `.glb` / `.gltf`. Host `GLBPreview` embeds `PreviewExtension` and `ThumbnailExtension`; shared code lives in `Shared/`.

## Commands

```bash
./scripts/build.sh            # xcodegen + Debug build + install to /Applications
./scripts/verify.sh           # check installed app + pluginkit
qlmanage -p path/to/file.glb  # preview proof
qlmanage -t path/to/file.glb  # thumbnail proof
./scripts/release.sh          # Developer ID + notary + Sparkle appcast + gh release
```

Signing team: `project.yml` (`DEVELOPMENT_TEAM`). Proof is `qlmanage`, not a browser.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -scheme GLBPreview -destination 'platform=macOS' \
  -derivedDataPath /tmp/GLBPreview-dd test
```
