import Renderer
import SwiftUI

/// The canvas **View** menu: live zoom on the button; Zoom / Fit / camera presets in the menu.
/// Shortcuts match the menu bar View menu.
struct ViewMenu: View {
    var view: ViewState

    var body: some View {
        DSGlassMenuButton(
            "View",
            systemImage: "viewfinder",
            style: .text("\(view.canvas.zoomPercent ?? 100)%"),
            help: "View — zoom, fit and camera angles"
        ) {
            ViewportZoomCommands(view: view)
            Divider()
            DSInlineMenuPicker("Camera", selection: preset) {
                ForEach(CameraPreset.allCases) { preset in
                    Label(preset.title, systemImage: preset.systemImage)
                        .tag(Optional(preset))
                        .keyboardShortcutIfAvailable(Shortcuts.cameraPreset(preset))
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
