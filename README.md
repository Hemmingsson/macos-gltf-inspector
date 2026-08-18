# GLB Quick Look

Personal fork of [DeepARSDK/glb-preview](https://github.com/DeepARSDK/glb-preview) with a native RealityKit Quick Look pipeline.

macOS Quick Look extension for previewing `.glb` (glTF Binary) files. Press spacebar on any `.glb` file in Finder to get an interactive 3D preview with orbit, pan and zoom.

![Finder preview of a shoe model](screenshots/finder-preview.png)
![Animation controls with scrubber](screenshots/animation-controls.png)

## Features

- Spacebar preview of `.glb` and sidecar `.gltf` files (`.bin` / textures next to the JSON) in Finder
- Interactive 3D viewer (orbit, pan, zoom)
- Animation playback with scrubber and pause
- Auto-rotate toggle (20°/s)
- Background colour toggle (dark/mid/light/white)
- Finder thumbnails framed to fill the icon (front 3/4)
- Spec/gloss materials rewritten natively (`GLBMetalRoughPrepare`) before load
- Fully offline (no network required)

## Fork changes

- **One renderer:** Spacebar preview and Finder icons both load with GLTFKit2 → RealityKit (`RealityView` / `RealityRenderer`).
- **Thumbnails:** Front 3/4 camera from visual bounds. File cameras in the asset are ignored. Mesh fills the square by framing, not a pixel crop.
- **Preview chrome:** Native overlay (backdrop cycle, auto-rotate, animation scrubber). Auto-rotate respects Reduce Motion.

## Install (pre-built)

1. Download [`GLBPreview.zip` from the latest release](https://github.com/DeepARSDK/glb-preview/releases/latest)
2. Unzip and drag `GLBPreview.app` to `/Applications`
3. Right-click the app > **Open**
4. macOS will show a warning that it cannot verify the app. Click **OK**, then go to **System Settings > Privacy & Security** and click **Open Anyway**:

![Gatekeeper prompt in Privacy & Security settings](screenshots/gatekeeper.png)

5. The app registers the Quick Look extensions on first launch — you're done

## Requirements

- macOS 15.0+

## Build from source

If you prefer to build from source:

```bash
# Install XcodeGen if you don't have it
brew install xcodegen

# Generate the Xcode project
cd glb-preview
xcodegen generate

# Open in Xcode
open GLBPreview.xcodeproj
```

In Xcode:

1. Select the **GLBPreview** scheme in the toolbar
2. Set your signing team on all three targets (GLBPreview, PreviewExtension, ThumbnailExtension) under **Signing & Capabilities**
3. Build with **Cmd+B**

Then install:

```bash
# Copy to Applications and reset Quick Look
rm -rf /Applications/GLBPreview.app
cp -R ~/Library/Developer/Xcode/DerivedData/GLBPreview-*/Build/Products/Debug/GLBPreview.app /Applications/
qlmanage -r
```

Open the app once to register the extensions:

```bash
open /Applications/GLBPreview.app
```

## Usage

- Select a `.glb` file in Finder and press **Space** to preview
- **Left-drag** to orbit
- **Scroll** to zoom
- Toolbar buttons (bottom left): background toggle, auto-rotate
- Scroll or pinch to zoom
- Animation controls appear at the bottom when the model has animations

## Set as default app for .glb files

Right-click any `.glb` file > **Get Info** > **Open With** > select **GLBPreview** > **Change All**

## Project structure

```
glb-preview/
├── project.yml                              # XcodeGen project spec
├── Shared/                                  # Load + viewer + 3/4 camera (both extensions)
│   ├── GLBEntityLoader.swift
│   ├── GLBPreviewCamera.swift
│   ├── GLBPreviewView.swift
│   ├── GLBMetalRoughPrepare.swift
│   ├── GLBDracoDecompressor.h
│   └── GLBDracoDecompressor.mm
├── GLBPreview/                              # Host app (minimal)
│   ├── GLBPreviewApp.swift
│   └── ContentView.swift
├── PreviewExtension/                        # Quick Look preview (spacebar)
│   └── PreviewViewController.swift
└── ThumbnailExtension/                      # Finder icon thumbnails
    └── ThumbnailProvider.swift
```
