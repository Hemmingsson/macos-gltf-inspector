import DesignSystem
import PreviewUI
import SwiftUI

/// Host View menu: drives `EngineViewportController` via `FocusedValues`.
///
/// Lives in `CommandGroup(after: .sidebar)` — never `CommandMenu("View")`. Sidebar visibility is
/// `SidebarCommands()` (⌃⌘S), kept in sync by `ShellPanelChrome.columnVisibility`.
struct HostViewMenuCommands: View {
    @FocusedValue(\.engineViewport) private var viewport
    @FocusedValue(\.previewCommands) private var previewCommands

    var body: some View {
        if let viewport {
            HostViewMenuBody(
                viewport: viewport,
                previewCommands: previewCommands
            )
        } else {
            Text("No focused window")
                .disabled(true)
        }
    }
}

private struct HostViewMenuBody: View {
    @Bindable var viewport: EngineViewportController
    var previewCommands: FocusedPreviewCommands?

    var body: some View {
        Picker("View Mode", selection: viewMode) {
            ForEach(ViewMode.base) { mode in
                Text(mode.title)
                    .tag(mode)
                    .keyboardShortcutIfAvailable(viewModeShortcut(for: mode))
            }
        }

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
        .keyboardShortcut(DS.Shortcuts.action(.autoRotate))

        Toggle("Center Model", systemImage: "dot.scope", isOn: center)
            .keyboardShortcut(DS.Shortcuts.action(.center))

        Toggle("Orthographic", systemImage: "perspective", isOn: orthographic)
            .keyboardShortcut(DS.Shortcuts.action(.orthographic))

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
        .keyboardShortcut(DS.Shortcuts.action(.fit))
        .disabled(previewCommands == nil)

        Button("Reset View", systemImage: "arrow.counterclockwise") {
            viewport.reset()
        }
        .keyboardShortcut(DS.Shortcuts.action(.reset))

        Divider()

        ForEach(CameraPreset.allCases) { preset in
            Button(
                preset.title,
                systemImage: EngineViewportController.previewCameraPreset(from: preset).menuSymbol
            ) {
                viewport.applyCameraPreset(preset)
            }
            .keyboardShortcutIfAvailable(cameraPresetShortcut(for: preset))
            .disabled(previewCommands == nil)
        }
    }

    private var viewMode: Binding<ViewMode> {
        Binding(
            get: { viewport.viewMode },
            set: { viewport.setViewMode($0) }
        )
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

    private func viewModeShortcut(for mode: ViewMode) -> KeyboardShortcut? {
        DS.Shortcuts.ViewMode(rawValue: mode.id).map(DS.Shortcuts.viewMode)
    }

    private func cameraPresetShortcut(for preset: CameraPreset) -> KeyboardShortcut? {
        DS.Shortcuts.CameraPreset(rawValue: preset.rawValue).flatMap(DS.Shortcuts.cameraPreset)
    }
}
