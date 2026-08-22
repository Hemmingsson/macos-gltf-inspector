import SwiftUI

/// Host View menu: drives `EngineViewportController` + panel chrome via `FocusedValues`.
///
/// Lives in `CommandGroup(after: .sidebar)` — never `CommandMenu("View")`.
struct HostViewMenuCommands: View {
    @FocusedValue(\.engineViewport) private var viewport
    @FocusedValue(\.shellPanelChrome) private var panels
    @FocusedValue(\.previewCommands) private var previewCommands

    var body: some View {
        // Panel toggles depend only on the window chrome, so they stay available even before a
        // model finishes loading (or after a failed load), when `viewport` is nil.
        if let panels {
            HostPanelChromeMenu(panels: panels)
        }
        if let viewport {
            if panels != nil {
                Divider()
            }
            HostViewMenuBody(
                viewport: viewport,
                previewCommands: previewCommands
            )
        } else if panels == nil {
            Text("No focused window")
                .disabled(true)
        }
    }
}

private struct HostViewMenuBody: View {
    @Bindable var viewport: EngineViewportController
    var previewCommands: FocusedPreviewCommands?

    var body: some View {
        Picker("Backdrop", selection: backdrop) {
            ForEach(BackdropStyle.allCases) { style in
                Text(style.title).tag(style)
            }
        }

        Toggle("Show Floor", systemImage: "circle.grid.cross", isOn: floor)
            .keyboardShortcut("l", modifiers: [.command])

        Toggle(
            "Auto-Rotate",
            systemImage: "arrow.trianglehead.counterclockwise.rotate.90",
            isOn: autoRotate
        )
        .keyboardShortcut("r", modifiers: [.command])

        Toggle("Center Model", systemImage: "dot.scope", isOn: center)
            .keyboardShortcut("c", modifiers: [.command, .shift])

        Toggle("Orthographic", systemImage: "perspective", isOn: orthographic)
            .keyboardShortcut("o", modifiers: [.command, .shift])

        Toggle("Double-Sided", systemImage: "square.on.square", isOn: doubleSided)
        Toggle(
            "Show Skeleton",
            systemImage: "point.3.connected.trianglepath.dotted",
            isOn: skeleton
        )
        Button("Widen FOV", systemImage: "plus.magnifyingglass") {
            viewport.setFieldOfViewDegrees(viewport.fieldOfViewDegrees + 5)
        }
        .disabled(viewport.projection == .orthographic)
        Button("Narrow FOV", systemImage: "minus.magnifyingglass") {
            viewport.setFieldOfViewDegrees(viewport.fieldOfViewDegrees - 5)
        }
        .disabled(viewport.projection == .orthographic)
        Button("Reset FOV", systemImage: "arrow.counterclockwise") {
            viewport.setFieldOfViewDegrees(PreviewCamera.defaultFieldOfViewDegrees)
        }

        Divider()

        Button("Fit", systemImage: "viewfinder") {
            viewport.fit()
        }
        .keyboardShortcut("0", modifiers: [.command])
        .disabled(previewCommands == nil)

        Button("Reset View", systemImage: "arrow.counterclockwise") {
            viewport.reset()
        }

        Button("Screenshot…", systemImage: "camera") {
            viewport.screenshot()
        }
        .disabled(previewCommands == nil)

        Divider()

        ForEach(CameraPreset.allCases) { preset in
            Button(preset.title, systemImage: hostPresetSymbol(preset)) {
                viewport.applyCameraPreset(preset)
            }
            .disabled(previewCommands == nil)
        }

        Divider()
        Button("Increase Exposure", systemImage: "sun.max") {
            nudgeExposure(0.5)
        }
        Button("Decrease Exposure", systemImage: "sun.min") {
            nudgeExposure(-0.5)
        }
        Button("Reset Exposure", systemImage: "sun.max.circle") {
            applyLighting { $0.exposure = 0 }
        }
        Toggle(
            "Dim Studio for File Lights",
            systemImage: "lightbulb.min",
            isOn: dimStudio
        )
        Button("Rotate Environment 45°", systemImage: "rotate.3d") {
            applyLighting { $0.environmentRotationDegrees += 45 }
        }
        Button("Reset Environment Rotation", systemImage: "arrow.counterclockwise") {
            applyLighting { $0.environmentRotationDegrees = 0 }
        }
    }

    private var backdrop: Binding<BackdropStyle> {
        Binding(
            get: { viewport.backdrop },
            set: { viewport.setBackdrop($0) }
        )
    }

    private var floor: Binding<Bool> {
        Binding(
            get: { viewport.showsFloor },
            set: { viewport.setFloor($0) }
        )
    }

    private var autoRotate: Binding<Bool> {
        Binding(
            get: { viewport.autoRotates },
            set: { viewport.setAutoRotate($0) }
        )
    }

    private var center: Binding<Bool> {
        Binding(
            get: { viewport.isCentered },
            set: { viewport.setCenter($0) }
        )
    }

    private var orthographic: Binding<Bool> {
        Binding(
            get: { viewport.projection == .orthographic },
            set: { viewport.setProjection($0 ? .orthographic : .perspective) }
        )
    }

    private var doubleSided: Binding<Bool> {
        Binding(
            get: { viewport.doubleSided },
            set: { viewport.setDoubleSided($0) }
        )
    }

    private var skeleton: Binding<Bool> {
        Binding(
            get: { viewport.showSkeleton },
            set: { viewport.setShowSkeleton($0) }
        )
    }

    private var dimStudio: Binding<Bool> {
        Binding(
            get: { viewport.lighting.usesFileLights },
            set: { isOn in applyLighting { $0.usesFileLights = isOn } }
        )
    }

    private func nudgeExposure(_ delta: Double) {
        applyLighting { $0.exposure += delta }
    }

    private func applyLighting(_ mutate: (inout LightingSettings) -> Void) {
        var lighting = viewport.lighting
        mutate(&lighting)
        viewport.setLighting(lighting)
    }

    private func hostPresetSymbol(_ preset: CameraPreset) -> String {
        switch preset {
        case .front: PreviewCamera.CameraPreset.front.menuSymbol
        case .back: PreviewCamera.CameraPreset.back.menuSymbol
        case .left: PreviewCamera.CameraPreset.left.menuSymbol
        case .right: PreviewCamera.CameraPreset.right.menuSymbol
        case .top: PreviewCamera.CameraPreset.top.menuSymbol
        case .bottom: PreviewCamera.CameraPreset.bottom.menuSymbol
        case .isometric: PreviewCamera.CameraPreset.iso.menuSymbol
        }
    }
}

private struct HostPanelChromeMenu: View {
    @Bindable var panels: ShellPanelChrome

    var body: some View {
        Toggle("Show Sidebar", isOn: $panels.isSidebarVisible)
            .keyboardShortcut("s", modifiers: [.command, .control])
    }
}
