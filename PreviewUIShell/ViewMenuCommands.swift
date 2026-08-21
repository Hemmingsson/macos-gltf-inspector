import SwiftUI

/// View-menu twin of the canvas pills **and** the sidebar / inspector chrome toggles.
/// Lives in `CommandGroup(after: .sidebar)` — never `CommandMenu("View")` (SwiftUI would insert
/// a second View menu between View and Window).
///
/// Drives the key window's `MockViewport` / `ShellPanelChrome` through `FocusedValues`, so
/// File → New Window keeps an independent session.
struct ViewMenuCommands: View {
    @FocusedValue(\.mockViewport) private var viewport
    @FocusedValue(\.shellPanelChrome) private var panels

    var body: some View {
        if let viewport {
            ViewMenuBody(viewport: viewport, panels: panels)
        } else {
            Text("No focused window")
                .disabled(true)
        }
    }
}

/// `@Bindable` lives here so `Toggle` / `Picker` can write the focused `@Observable` viewport.
private struct ViewMenuBody: View {
    @Bindable var viewport: MockViewport
    var panels: ShellPanelChrome?

    var body: some View {
        if let panels {
            PanelChromeMenu(panels: panels)
            Divider()
        }

        Picker("Backdrop", selection: backdrop) {
            ForEach(BackdropStyle.allCases) { style in
                Text(style.title).tag(style)
            }
        }

        Toggle("Show Floor", isOn: floor)
            .keyboardShortcut("l", modifiers: [.command])

        Divider()

        Toggle("Auto-Rotate", isOn: autoRotate)
            .keyboardShortcut("r", modifiers: [.command])

        Toggle("Center", isOn: center)
            .keyboardShortcut("c", modifiers: [.command, .shift])

        Toggle("Orthographic", isOn: orthographic)
            .keyboardShortcut("o", modifiers: [.command, .shift])

        Divider()

        Button("Fit") {
            viewport.fit()
        }
        .keyboardShortcut("0", modifiers: [.command])

        Picker("Camera Preset", selection: preset) {
            ForEach(CameraPreset.allCases) { preset in
                Text(preset.title).tag(Optional(preset))
            }
        }

        Divider()

        Button("Reset View") {
            viewport.reset()
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

    private var preset: Binding<CameraPreset?> {
        Binding(
            get: { viewport.activeCameraPreset },
            set: { newValue in
                if let newValue {
                    viewport.applyCameraPreset(newValue)
                }
            }
        )
    }
}

private struct PanelChromeMenu: View {
    @Bindable var panels: ShellPanelChrome

    var body: some View {
        Toggle("Show Sidebar", isOn: $panels.isSidebarVisible)
            .keyboardShortcut("s", modifiers: [.command, .control])

        Toggle("Show Inspector", isOn: $panels.isInspectorVisible)
            .keyboardShortcut("i", modifiers: [.command, .control])
    }
}
