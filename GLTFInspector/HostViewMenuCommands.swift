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
        Picker("View Mode", selection: bind(\.viewMode, viewport.setViewMode)) {
            ForEach(ViewMode.base) { mode in
                Text(mode.title)
                    .tag(mode)
                    .keyboardShortcutIfAvailable(viewModeShortcut(for: mode))
            }
        }

        Picker("Backdrop", selection: bind(\.backdrop, viewport.setBackdrop)) {
            ForEach(BackdropStyle.allCases) { style in
                Text(style.title).tag(style)
            }
        }

        Toggle("Show Floor", systemImage: "circle.grid.cross", isOn: bind(\.showsFloor, viewport.setFloor))

        Toggle(
            "Auto-Rotate",
            systemImage: "arrow.trianglehead.counterclockwise.rotate.90",
            isOn: bind(\.autoRotates, viewport.setAutoRotate)
        )
        .keyboardShortcut(DS.Shortcuts.action(.autoRotate))

        Toggle("Center Model", systemImage: "dot.scope", isOn: bind(\.isCentered, viewport.setCenter))
            .keyboardShortcut(DS.Shortcuts.action(.center))

        Toggle("Orthographic", systemImage: "perspective", isOn: orthographic)
            .keyboardShortcut(DS.Shortcuts.action(.orthographic))

        ForEach(HostViewMenuAvailability.toggles(for: viewport.features), id: \.self) { item in
            switch item {
            case .doubleSided:
                Toggle(
                    "Double-Sided",
                    systemImage: "square.on.square",
                    isOn: bind(\.doubleSided, viewport.setDoubleSided)
                )
            case .showSkeleton:
                Toggle(
                    "Show Skeleton",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    isOn: bind(\.showSkeleton, viewport.setShowSkeleton)
                )
            }
        }

        Divider()

        Button("Fit", systemImage: "viewfinder") {
            viewport.fit()
        }
        .keyboardShortcut(DS.Shortcuts.action(.fit))
        .disabled(viewport.commands == nil)

        Button("Reset View", systemImage: "arrow.counterclockwise") {
            viewport.reset()
        }
        .keyboardShortcut(DS.Shortcuts.action(.reset))

        Divider()

        ForEach(CameraPreset.allCases) { preset in
            Button(
                preset.title,
                systemImage: Self.menuSymbol(for: preset)
            ) {
                viewport.applyCameraPreset(preset)
            }
            .keyboardShortcutIfAvailable(cameraPresetShortcut(for: preset))
            .disabled(viewport.commands == nil)
        }
    }

    /// A menu binding over a viewport getter and its setter (the setter owns the side effects).
    private func bind<Value>(
        _ get: KeyPath<EngineViewportController, Value>,
        _ set: @escaping (Value) -> Void
    ) -> Binding<Value> {
        Binding(get: { viewport[keyPath: get] }, set: set)
    }

    /// SF Symbols for the View menu (the Camera cluster uses `cube` for the group).
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
