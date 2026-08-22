import SwiftUI

/// Host View menu: drives `EngineViewportController` + panel chrome via `FocusedValues`,
/// and keeps double-sided / skeleton / FOV / lighting on `FocusedPreviewSession`.
///
/// Lives in `CommandGroup(after: .sidebar)` — never `CommandMenu("View")`.
struct HostViewMenuCommands: View {
    @FocusedValue(\.engineViewport) private var viewport
    @FocusedValue(\.shellPanelChrome) private var panels
    @FocusedValue(\.previewCommands) private var previewCommands
    @FocusedValue(\.previewSession) private var previewSession

    var body: some View {
        if let viewport {
            HostViewMenuBody(
                viewport: viewport,
                panels: panels,
                previewCommands: previewCommands,
                previewSession: previewSession
            )
        } else {
            Text("No focused window")
                .disabled(true)
        }
    }
}

private struct HostViewMenuBody: View {
    @Bindable var viewport: EngineViewportController
    var panels: ShellPanelChrome?
    var previewCommands: FocusedPreviewCommands?
    var previewSession: FocusedPreviewSession?

    var body: some View {
        if let panels {
            HostPanelChromeMenu(panels: panels)
            Divider()
        }

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

        if let previewSession {
            Toggle("Double-Sided", systemImage: "square.on.square", isOn: previewSession.doubleSided)
            Toggle(
                "Show Skeleton",
                systemImage: "point.3.connected.trianglepath.dotted",
                isOn: previewSession.showSkeleton
            )
            Button("Widen FOV", systemImage: "plus.magnifyingglass") {
                previewSession.fieldOfViewDegrees.wrappedValue = PreviewCamera.clampedFieldOfView(
                    previewSession.fieldOfViewDegrees.wrappedValue + 5
                )
            }
            .disabled(previewSession.orthographic.wrappedValue)
            Button("Narrow FOV", systemImage: "minus.magnifyingglass") {
                previewSession.fieldOfViewDegrees.wrappedValue = PreviewCamera.clampedFieldOfView(
                    previewSession.fieldOfViewDegrees.wrappedValue - 5
                )
            }
            .disabled(previewSession.orthographic.wrappedValue)
            Button("Reset FOV", systemImage: "arrow.counterclockwise") {
                previewSession.fieldOfViewDegrees.wrappedValue = PreviewCamera.defaultFieldOfViewDegrees
            }
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

        if let previewSession {
            Divider()
            Button("Increase Exposure", systemImage: "sun.max") {
                previewSession.exposureEV.wrappedValue += 0.5
            }
            Button("Decrease Exposure", systemImage: "sun.min") {
                previewSession.exposureEV.wrappedValue -= 0.5
            }
            Button("Reset Exposure", systemImage: "sun.max.circle") {
                previewSession.exposureEV.wrappedValue = 0
            }
            Toggle(
                "Dim Studio for File Lights",
                systemImage: "lightbulb.min",
                isOn: previewSession.dimStudioForFileLights
            )
            Button("Rotate Environment 45°", systemImage: "rotate.3d") {
                previewSession.environmentYaw.wrappedValue += .pi / 4
            }
            Button("Reset Environment Rotation", systemImage: "arrow.counterclockwise") {
                previewSession.environmentYaw.wrappedValue = 0
            }
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
        Toggle("Show Inspector", isOn: $panels.isInspectorVisible)
            .keyboardShortcut("i", modifiers: [.command, .control])
    }
}
