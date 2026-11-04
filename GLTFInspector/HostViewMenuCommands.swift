import DesignSystem
import PreviewUI
import SwiftUI

/// Host View menu: drives `EngineViewportController` via `FocusedValues`.
///
/// Lives in `CommandGroup(after: .sidebar)` — never `CommandMenu("View")`. Sidebar visibility is
/// `SidebarCommands()` (⌃⌘S), kept in sync by `ShellPanelChrome.columnVisibility`.
struct HostViewMenuCommands: View {
    @FocusedValue(\.engineViewport) private var viewport

    var body: some View {
        if let viewport {
            HostViewMenuBody(viewport: viewport)
        } else {
            Text("No focused window")
                .disabled(true)
        }
    }
}

private struct HostViewMenuBody: View {
    let viewport: EngineViewportController

    var body: some View {
        Picker(selection: bind(\.viewMode, viewport.setViewMode)) {
            ForEach(ViewMode.base) { mode in
                Label(mode.title, systemImage: mode.systemImage)
                    .tag(mode)
                    .keyboardShortcutIfAvailable(viewModeShortcut(for: mode))
            }
        } label: {
            Label("View Mode", systemImage: MenuSymbol.viewMode)
        }
        .menuBarIcons()

        Picker(selection: bind(\.backdrop, viewport.setBackdrop)) {
            ForEach(BackdropStyle.allCases) { style in
                Label(style.title, systemImage: style.systemImage)
                    .tag(style)
            }
        } label: {
            Label("Backdrop", systemImage: MenuSymbol.backdrop)
        }
        .menuBarIcons()

        Toggle("Show Floor", systemImage: MenuSymbol.floor, isOn: bind(\.showsFloor, viewport.setFloor))
            .menuBarIcons()

        Toggle(
            "Auto-Rotate",
            systemImage: MenuSymbol.autoRotate,
            isOn: bind(\.autoRotates, viewport.setAutoRotate)
        )
        .keyboardShortcut(DS.Shortcuts.action(.autoRotate))
        .menuBarIcons()

        Toggle("Center Model", systemImage: MenuSymbol.center, isOn: bind(\.isCentered, viewport.setCenter))
            .keyboardShortcut(DS.Shortcuts.action(.center))
            .menuBarIcons()

        Toggle("Orthographic", systemImage: MenuSymbol.orthographic, isOn: orthographic)
            .keyboardShortcut(DS.Shortcuts.action(.orthographic))
            .menuBarIcons()

        Divider()

        Button("Zoom In", systemImage: MenuSymbol.zoomIn) {
            viewport.zoom(by: 0.8)
        }
        .keyboardShortcut(DS.Shortcuts.action(.zoomIn))
        .disabled(viewport.commands == nil)
        .menuBarIcons()

        Button("Zoom Out", systemImage: MenuSymbol.zoomOut) {
            viewport.zoom(by: 1 / 0.8)
        }
        .keyboardShortcut(DS.Shortcuts.action(.zoomOut))
        .disabled(viewport.commands == nil)
        .menuBarIcons()

        Button("Fit", systemImage: MenuSymbol.fit) {
            viewport.fit()
        }
        .keyboardShortcut(DS.Shortcuts.action(.fit))
        .disabled(viewport.commands == nil)
        .menuBarIcons()

        Button("Reset View", systemImage: MenuSymbol.reset) {
            viewport.reset()
        }
        .keyboardShortcut(DS.Shortcuts.action(.reset))
        .menuBarIcons()

        Divider()

        ForEach(CameraPreset.allCases) { preset in
            Button(preset.title, systemImage: preset.systemImage) {
                viewport.applyCameraPreset(preset)
            }
            .keyboardShortcutIfAvailable(cameraPresetShortcut(for: preset))
            .disabled(viewport.commands == nil)
            .menuBarIcons()
        }
    }

    /// A menu binding over a viewport getter and its setter (the setter owns the side effects).
    private func bind<Value>(
        _ get: KeyPath<EngineViewportController, Value>,
        _ set: @escaping (Value) -> Void
    ) -> Binding<Value> {
        Binding(get: { viewport[keyPath: get] }, set: set)
    }

    private var orthographic: Binding<Bool> {
        Binding(
            get: { viewport.projection == .orthographic },
            set: { viewport.setProjection($0 ? .orthographic : .perspective) }
        )
    }

    private func viewModeShortcut(for mode: ViewMode) -> KeyboardShortcut? {
        DS.Shortcuts.ViewMode(rawValue: mode.id).map(DS.Shortcuts.viewMode)
    }

    private func cameraPresetShortcut(for preset: CameraPreset) -> KeyboardShortcut? {
        DS.Shortcuts.CameraPreset(rawValue: preset.rawValue).flatMap(DS.Shortcuts.cameraPreset)
    }
}
