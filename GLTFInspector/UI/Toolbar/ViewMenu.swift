import Renderer
import SwiftUI

/// The canvas **View** menu, like a design tool's zoom menu: the button reads the live zoom
/// (100% = fitted); the menu holds Zoom In / Zoom Out, Fit, then the canned camera angles with a
/// checkmark on the active one. Shortcuts match the menu bar's View menu.
struct ViewMenu: View {
    var view: ViewState

    var body: some View {
        DSGlassMenuButton(
            "View",
            systemImage: "viewfinder",
            style: .text("\(view.canvas.zoomPercent ?? 100)%"),
            help: "View — zoom, fit and camera angles"
        ) {
            Button("Zoom In", systemImage: "plus.magnifyingglass") { view.zoom(by: ViewState.zoomStep) }
                .keyboardShortcut(DS.Shortcuts.action(.zoomIn))
            Button("Zoom Out", systemImage: "minus.magnifyingglass") { view.zoom(by: 1 / ViewState.zoomStep) }
                .keyboardShortcut(DS.Shortcuts.action(.zoomOut))
            Divider()
            Button("Fit Model", systemImage: "arrow.down.right.and.arrow.up.left") { view.fit() }
                .keyboardShortcut(DS.Shortcuts.action(.fit))
            Divider()
            DSInlineMenuPicker("Camera", selection: preset) {
                ForEach(CameraPreset.allCases) { preset in
                    Label(preset.title, systemImage: preset.systemImage)
                        .tag(Optional(preset))
                        .keyboardShortcutIfAvailable(DS.Shortcuts.cameraPreset(preset))
                }
            }
        }
    }

    private var preset: Binding<CameraPreset?> {
        Binding(
            get: { view.activeCameraPreset },
            set: { if let preset = $0 { view.show(preset) } }
        )
    }
}
