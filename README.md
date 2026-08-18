# macOS glTF Preview

Spacebar preview and Finder icons for `.glb` / `.gltf`. macOS 15+.

Drag to orbit, scroll to zoom. Play / pause if the file has animations.

![Preview](screenshots/preview.gif)
![Quick Look](screenshots/quick-look.gif)

## Install

[GLBPreview.zip](https://github.com/Hemmingsson/macos-gltf-preview/releases/latest) → `/Applications`. Right-click → Open. Gatekeeper: **System Settings → Privacy & Security → Open Anyway**. Launch once.

Finder → file → Space.

## Build

Xcode, [XcodeGen](https://github.com/yonaskolb/XcodeGen), [ffmpeg](https://ffmpeg.org), team ID in `project.yml` (`DEVELOPMENT_TEAM`).

```bash
brew install xcodegen ffmpeg
./scripts/verify.sh --build
```

`--build` also writes `screenshots/preview.gif` (360° of DamagedHelmet composited onto `screenshots/base-image.png`).

Started from [DeepAR's glb-preview](https://github.com/DeepARSDK/glb-preview) Quick Look / thumbnail skeleton; rewritten to native RealityKit.
