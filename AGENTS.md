# GLB Preview

macOS 15+ Quick Look + Finder thumbnails for `.glb` / `.gltf`. Host `GLBPreview` embeds `PreviewExtension` and `ThumbnailExtension`. Convert/render live in `Shared/` (+ `Shared/Convert/`); host outliner and settings live in `GLBPreview/`.

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

Ledger and protocol: `experiments/` (`PROTOCOL.md`, `results.json`, `WHAT-WE-TRIED.md`). Bench: `LABEL=<id> ./scripts/load-bench.sh`.
