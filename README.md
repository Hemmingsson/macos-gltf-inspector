<div align="center">

<img src="assets/icon.png" width="128" alt="glTF Inspector">

# glTF Inspector

Open and inspect `.glb` and `.gltf` models on your Mac.
Preview them in Finder with Quick Look and thumbnails.

<a href="https://github.com/Hemmingsson/macos-gltf-inspector/releases/latest"><img src="https://img.shields.io/github/v/release/Hemmingsson/macos-gltf-inspector?label=release" alt="Latest release"></a>
<img src="https://img.shields.io/badge/macOS-26%2B-111111" alt="macOS 26 or later">
<img src="https://img.shields.io/badge/Swift-native-F05138" alt="Native Swift app">

</div>

Native Swift macOS app for opening [glTF 2.0](https://www.khronos.org/gltf/) models with
Metal. The app, Quick Look, and Finder thumbnails share one renderer with shading adapted
from the Khronos glTF Sample Renderer.

<p align="center">
  <img src="assets/readme/screenshot.png" width="100%" alt="glTF Inspector showing a model with the material inspector open"><br>
  <small>App</small>
</p>

<table>
  <tr>
    <td align="center" valign="top" width="33%">
      <img src="assets/mockups/finder-thumbnails.png" alt="Finder thumbnails for .glb and .gltf files"><br>
      <small>Thumbnails</small>
    </td>
    <td align="center" valign="top" width="33%">
      <img src="assets/mockups/quick-look.webp" alt="Quick Look preview of a .glb file"><br>
      <small>Quick Look</small>
    </td>
    <td align="center" valign="top" width="33%">
      <img src="assets/mockups/preview-pane.webp" alt="Finder preview pane for a .glb file"><br>
      <small>Preview pane</small>
    </td>
  </tr>
</table>

## Install

macOS 26+ on Apple Silicon.

1. Download [glTFInspector.zip](https://github.com/Hemmingsson/macos-gltf-inspector/releases/latest/download/glTFInspector.zip).
2. Unzip and open **glTF Inspector.app**. If it is outside **Applications**, the app offers to copy itself there and relaunch. If a copy is already installed, replace it in Finder.
3. Open the app once to register Quick Look and thumbnails.

[Release notes](https://github.com/Hemmingsson/macos-gltf-inspector/releases/latest) · [Build from source](docs/development.md)

## Use

Open a model in the app, or select one in Finder and press **Space**.
For `.gltf`, keep buffers and textures next to the file.

- Drag to orbit, **Shift-drag** to pan, scroll to zoom
- Select a sidebar row to inspect nodes, meshes, and materials
- Change lighting and view mode, or play an animation
- Export a PNG, or a turntable as MP4 or GIF

[Controls and shortcuts](docs/usage.md)

## Development

```sh
brew install xcodegen
./scripts/dev.sh build
```

Signing and App Group setup come first — see [development](docs/development.md).
Also: [architecture](docs/architecture.md), [design](docs/design.md), [contributing](CONTRIBUTING.md).

## License

[MIT](LICENSE). Third-party notices:
[dependencies](GLTFInspector/Resources/ThirdPartyLicenses),
[lighting images](Renderer/Environments/LICENSES.md).

