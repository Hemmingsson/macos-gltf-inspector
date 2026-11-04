import Renderer
import SwiftUI

/// The menu bar's View menu items for the key document window: the full command set, with the
/// same shortcuts as the canvas controls.
///
/// Lives in `CommandGroup(after: .sidebar)`, never `CommandMenu("View")`. Sidebar visibility is
/// `SidebarCommands()` (⌃⌘S), kept in sync by `ShellPanelChrome.columnVisibility`.
struct ViewMenuCommands: View {
    @FocusedValue(\.documentWindow) private var window

    var body: some View {
        if let view = window?.view {
            ViewMenuItems(view: view)
        } else {
            Text("No focused window")
                .disabled(true)
        }
    }
}

private struct ViewMenuItems: View {
    @Bindable var view: ViewState

    var body: some View {
        Picker("View Mode", selection: $view.viewMode) {
            ForEach(view.viewModes.filter { $0 == .shaded || $0 == .wireframe }, id: \.self) { mode in
                Text(mode.title)
                    .tag(mode)
                    .keyboardShortcutIfAvailable(DS.Shortcuts.viewMode(mode))
            }
        }

        Picker("Backdrop", selection: $view.backdrop) {
            ForEach(BackdropStyle.allCases) { style in
                Text(style.title).tag(style)
            }
        }

        Toggle("Show Floor", systemImage: "circle.grid.cross", isOn: $view.showsFloor)

        Toggle("Auto-Rotate", systemImage: "arrow.trianglehead.counterclockwise.rotate.90", isOn: $view.autoRotates)
            .keyboardShortcut(DS.Shortcuts.action(.autoRotate))

        Toggle("Center Model", systemImage: "dot.scope", isOn: $view.isCentered)
            .keyboardShortcut(DS.Shortcuts.action(.center))

        Toggle("Orthographic", systemImage: "perspective", isOn: $view.isOrthographic)
            .keyboardShortcut(DS.Shortcuts.action(.orthographic))

        Divider()

        Group {
            Button("Zoom In", systemImage: "plus.magnifyingglass") { view.zoom(by: ViewState.zoomStep) }
                .keyboardShortcut(DS.Shortcuts.action(.zoomIn))
            Button("Zoom Out", systemImage: "minus.magnifyingglass") { view.zoom(by: 1 / ViewState.zoomStep) }
                .keyboardShortcut(DS.Shortcuts.action(.zoomOut))
            Button("Fit", systemImage: "viewfinder") { view.fit() }
                .keyboardShortcut(DS.Shortcuts.action(.fit))
        }
        .disabled(view.canvas.phase != .ready)

        Button("Reset View", systemImage: "arrow.counterclockwise") { view.resetView() }
            .keyboardShortcut(DS.Shortcuts.action(.reset))

        Divider()

        ForEach(CameraPreset.allCases) { preset in
            Button(preset.title, systemImage: preset.systemImage) { view.show(preset) }
                .keyboardShortcutIfAvailable(DS.Shortcuts.cameraPreset(preset))
        }
        .disabled(view.canvas.phase != .ready)
    }
}
