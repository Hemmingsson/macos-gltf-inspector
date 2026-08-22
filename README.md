<p align="center">
  <img src="assets/icon.png" width="175" alt="glTF Inspector">
</p>

<h1 align="center">macOS glTF Inspector</h1>

<p align="center">
  <strong>Native App and Finder Support for <code>.glb</code> and <code>.gltf</code> Using <a href="https://developer.apple.com/documentation/realitykit">RealityKit</a></strong><br>
  Inspector App, Thumbnails, Quick Look and Preview Pane
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



## Install

1. Download [glTFInspector.zip](https://github.com/Hemmingsson/macos-gltf-inspector/releases/latest).
2. Move `glTF Inspector.app` to `/Applications`.
3. Control-click → **Open** (or allow under **System Settings → Privacy & Security**).
4. Open the app once so the Quick Look preview and thumbnail extensions load.

## Build

Requires Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen). Set `DEVELOPMENT_TEAM` in `project.yml`.

1. `brew install xcodegen`
2. `./scripts/build.sh`

This generates the Xcode project, builds, installs to `/Applications`, and checks that the Quick Look extensions registered.

```bash
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -scheme GLTFInspector -destination 'platform=macOS' \
  -derivedDataPath /tmp/GLTFInspector-dd test
```

## How it works

RealityKit does not load glTF by default. The file is prepared, decoded with [GLTFKit2](https://github.com/warrenm/GLTFKit2) (Draco via [DracoSwift](https://github.com/warrenm/DracoSwift)), and converted to a RealityKit `Entity`.

```mermaid
flowchart LR
  file[".glb / .gltf"] --> prep["Prepare + GLTFKit2"]
  prep --> rk["RealityKit Entity"]
  rk --> host["Host app\nPreviewUI shell + RealityView"]
  rk --> ql["Quick Look\norbit + facts + two buttons"]
  rk --> thumb["Finder thumbnail\nRealityRenderer"]
```

Prepare rewrites materials and meshes RealityKit will not ingest, then the default scene is converted to a physically based entity on a turntable.

The host app window is **`PreviewUI`** chrome (sidebar, inspector, pills, settings) over a real **`PreviewView`** canvas. Thin **`GLTFInspector/Engine/`** adapters map the existing engine (`HostSidebarModel`, `EntityLoader`, `AppLook`) onto the UI seam.

App and Quick Look show that entity in a `RealityView` with studio IBL for light and reflections — not a skybox. Quick Look is a light canvas (orbit, bottom-left facts, backdrop + auto-rotate). Finder thumbnails are a still from `RealityRenderer`.

