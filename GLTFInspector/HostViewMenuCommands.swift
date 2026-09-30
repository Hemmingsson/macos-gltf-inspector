import PreviewUI
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

        Toggle(
            "Auto-Rotate",
            systemImage: "arrow.trianglehead.counterclockwise.rotate.90",
            isOn: autoRotate
        )
        .keyboardShortcut("r")

        Toggle("Center Model", systemImage: "dot.scope", isOn: center)
            .keyboardShortcut("c")

        Toggle("Orthographic", systemImage: "perspective", isOn: orthographic)
            .keyboardShortcut("5")

        Toggle("Double-Sided", systemImage: "square.on.square", isOn: doubleSided)
        Toggle(
            "Show Skeleton",
            systemImage: "point.3.connected.trianglepath.dotted",
            isOn: skeleton
        )

        Divider()

        Button("Fit", systemImage: "viewfinder") {
            viewport.fit()
        }
        .keyboardShortcut("f")
        .disabled(previewCommands == nil)

        Button("Reset View", systemImage: "arrow.counterclockwise") {
            viewport.reset()
        }
        .keyboardShortcut("f", modifiers: [.shift])

        Divider()

        ForEach(CameraPreset.allCases) { preset in
            Button(
                preset.title,
                systemImage: Self.menuSymbol(for: preset)
            ) {
                viewport.applyCameraPreset(preset)
            }
            .keyboardShortcutIfAvailable(cameraPresetShortcut(for: preset))
            .disabled(previewCommands == nil)
        }

    }

    /// SF Symbols for the View menu (the Camera pill uses `cube` for the group).
    private static func menuSymbol(for preset: CameraPreset) -> String {
        switch preset {
        case .front: "arrow.up.to.line"
        case .back: "arrow.down.to.line"
        case .left: "arrow.left.to.line"
        case .right: "arrow.right.to.line"
        case .top: "arrow.up.to.line.compact"
        case .bottom: "arrow.down.to.line.compact"
        case .isometric: "cube"
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

    private func cameraPresetShortcut(for preset: CameraPreset) -> KeyboardShortcut? {
        switch preset {
        case .front: KeyboardShortcut("1")
        case .back: KeyboardShortcut("9")
        case .left: KeyboardShortcut("4")
        case .right: KeyboardShortcut("3")
        case .top: KeyboardShortcut("7")
        case .bottom: KeyboardShortcut("2")
        case .isometric: nil
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
