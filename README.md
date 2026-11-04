<p align="center">
  <img src="assets/icon.png" width="175" alt="glTF Inspector">
</p>

<h1 align="center">macOS glTF Inspector</h1>

<p align="center">
  <strong>Native App and Finder Support for <code>.glb</code> and <code>.gltf</code></strong><br>
  Inspector App, Thumbnails, Quick Look and Preview Pane — rendered by a Metal port of the <a href="https://github.com/KhronosGroup/glTF-Sample-Renderer">Khronos glTF Sample Renderer</a>
</p>

<table>
  <tr>
    <td align="center" valign="top" width="50%">
      <img src="assets/app_window.webp" alt="App window preview of a spinning .glb file">
      <small>Viewer App</small>
    </td>
    <td align="center" valign="top" width="50%">
      <img src="assets/finder_thumbnails.png" alt="Finder thumbnail previews for .glb / .gltf files">
      <small>Thumbnails</small>
    </td>
  </tr>
  <tr>
    <td align="center" valign="top" width="50%">
      <img src="assets/quick_look.webp" alt="Quick Look preview of a .glb file, model spinning">
      <small>Quick Look</small>
    </td>
    <td align="center" valign="top" width="50%">
      <img src="assets/finder_details_pane.webp" alt="Finder open-panel preview of a spinning .glb file">
      <small>Preview Pane</small>
    </td>
  </tr>
</table>

The same renderer draws the model in the app, in Quick Look and in Finder. There is no renderer
setting. Lighting, cameras and view mode change the picture; the geometry is shown as authored, in
its rest pose.

## Install

1. Download [glTFInspector.zip](https://github.com/Hemmingsson/macos-gltf-inspector/releases/latest).
2. Move `glTF Inspector.app` to `/Applications`.
3. Control-click → **Open** (or allow under **System Settings → Privacy & Security**).
4. Open the app once so the Quick Look preview and thumbnail extensions load.

## Build

Requires macOS 26+ on Apple Silicon, Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen). Set `DEVELOPMENT_TEAM` in `project.yml` to your own Apple Developer team.

1. `brew install xcodegen`
2. `./scripts/build.sh`

This generates the Xcode project, builds, installs to `/Applications`, and checks that the Quick Look extensions registered.

```bash
./scripts/dev.sh test
```

Renderer tests need the Khronos samples on disk (`./scripts/fetch-test-models.sh`); missing
samples fail rather than skip. See
[`TestModels/References/README.md`](TestModels/References/README.md).

## How it works

The renderer is a native Metal port of the [Khronos glTF Sample Renderer](https://github.com/KhronosGroup/glTF-Sample-Renderer)
(`Renderer/`). The window and Quick Look draw it live; Finder thumbnails render one frame off
screen. Its output is tested against images rendered by the Khronos renderer itself
([`TestModels/References/`](TestModels/References/README.md)).

The outliner and inspector describe the **file**: they read its glTF JSON (`GLTFDocument`), not
what the renderer kept, and the Khronos glTF-Validator reports problems in it.

Settings (lighting defaults, backdrop, floor) live in an App Group so the sandboxed Quick Look and
thumbnail extensions read the same values as the app.

Details: [`docs/architecture.md`](docs/architecture.md).

## License

Released under the [MIT License](LICENSE). [Sparkle](https://github.com/sparkle-project/Sparkle) is MIT-licensed. The Metal port of the [Khronos glTF Sample Renderer](Renderer/Shaders) is Apache-2.0. The [Khronos glTF-Validator](Vendor/gltf-validator) and IBL environments carry their own licenses in-tree.
