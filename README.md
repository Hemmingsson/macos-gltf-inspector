<p align="center">
  <img src="assets/icon.png" width="128" height="128" alt="GLB Preview">
</p>

# macOS glTF Preview

Quick Look previews and Finder thumbnails for `.glb` and `.gltf` on macOS 15+.

- Finder preview pane for `.glb` / `.gltf`.
- Quick Look (Space) with orbit, zoom, and play / pause for animations.
- Finder icon thumbnails.
- Mesh, material, and animation counts in Quick Look.

<p align="center">
  <img src="assets/exported/quick_look.webp" alt="Quick Look preview of a .glb file, model spinning">
</p>

<table>
  <tr>
    <td align="center" valign="top" width="50%">
      <img src="assets/exported/app_window.webp" alt="App window preview of a spinning .glb file">
    </td>
    <td align="center" valign="top" width="50%">
      <img src="assets/exported/finder_details_pane.webp" alt="Finder open-panel preview of a spinning .glb file">
    </td>
  </tr>
</table>

<p align="center">
  <img src="assets/exported/finder_thumbnails.webp" alt="Finder thumbnail previews for .glb / .gltf files">
</p>

## Install

1. Download [GLBPreview.zip](https://github.com/Hemmingsson/macos-gltf-preview/releases/latest).
2. Move `GLBPreview.app` to `/Applications`.
3. Control-click → **Open** (or allow under **System Settings → Privacy & Security**).
4. Open the app once so the Quick Look preview and thumbnail extensions load.

## Build

Requires Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen). Set `DEVELOPMENT_TEAM` in `project.yml`.

1. `brew install xcodegen`
2. `./scripts/verify.sh --build`

This generates the Xcode project, builds, and installs to `/Applications`.

## How it works

`.glb` / `.gltf` are loaded with [GLTFKit2](https://github.com/warrenm/GLTFKit2) (Draco via [DracoSwift](https://github.com/warrenm/DracoSwift)). Specular-glossiness materials are converted to metallic-roughness when needed, then the asset becomes a RealityKit `Entity`. The Quick Look preview extension shows it in a `RealityView`; the thumbnail extension draws Finder icons with `RealityRenderer`.

```mermaid
flowchart LR
  file[".glb / .gltf"] --> prep["Prepare + GLTFKit2"]
  prep --> rk["RealityKit Entity"]
  rk --> ql["Quick Look\nRealityView"]
  rk --> thumb["Finder thumbnail\nRealityRenderer"]
```

Thanks to [DeepAR's glb-preview](https://github.com/DeepARSDK/glb-preview) for the Quick Look and thumbnail extension layout. That project used SceneKit (deprecated); this app uses RealityKit.
