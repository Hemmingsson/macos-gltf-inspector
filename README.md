<p align="center">
  <img src="screenshots/icon.png" width="128" height="128" alt="GLB Preview">
</p>

# macOS glTF Preview

Spacebar preview / Quick Look and Finder thumbnails for `.glb` / `.gltf`. macOS 15+.

- Drag to orbit, scroll to zoom.
- Play / pause if the file has animations.
- Mesh, material, and animation counts in the viewer.

<p align="center">
  <strong>Preview .gltf/.glb files in Finder</strong><br>
  <img src="screenshots/preview.gif" alt="Finder preview of a glTF model">
</p>

<table>
  <tr>
    <td align="center" valign="top" width="50%">
      <strong>Quick Look</strong><br>
      <img src="screenshots/quick-look.gif" alt="Quick Look">
    </td>
    <td align="center" valign="top" width="50%">
      <strong>Thumbnails</strong><br>
      <img src="screenshots/finder-thumbnail.png" alt="Finder Thumbnails">
    </td>
  </tr>
</table>

## Install

[GLBPreview.zip](https://github.com/Hemmingsson/macos-gltf-preview/releases/latest) → `/Applications`. Right-click → Open. Gatekeeper: **System Settings → Privacy & Security → Open Anyway**. Launch once.

## Build

Xcode, [XcodeGen](https://github.com/yonaskolb/XcodeGen), [ffmpeg](https://ffmpeg.org), team ID in `project.yml` (`DEVELOPMENT_TEAM`).

```bash
brew install xcodegen ffmpeg
./scripts/verify.sh --build
```

`--build` also writes `screenshots/icon.png` and the README GIFs (`./scripts/publish.sh`).

Started from [DeepAR's glb-preview](https://github.com/DeepARSDK/glb-preview) Quick Look / thumbnail skeleton; rewritten to native RealityKit.
