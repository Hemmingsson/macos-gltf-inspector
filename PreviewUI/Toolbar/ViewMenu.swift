import DesignSystem
import SwiftUI

/// The canvas **View** menu, like a design tool's zoom menu: the button reads the live zoom
/// ("90%", 100% = fitted); the menu holds Zoom In / Zoom Out, Fit, then the canned camera angles
/// (Front · Back · … · Isometric) with a checkmark on the active one. Every item has an icon.
///
/// One text glass capsule in the Camera cluster. Shortcuts come from `DS.Shortcuts` and match
/// the menu bar's View menu, which carries the same commands while this menu is closed.
struct ViewMenu<Viewport: ViewportController>: View {
    var viewport: Viewport

    /// One step of Zoom In; Zoom Out is its inverse so the two cancel.
    static var zoomStep: Double { 0.8 }

    var body: some View {
        DSGlassMenuButton(
            "View",
            systemImage: "viewfinder",
            style: .text(zoomLabel),
            help: "View — zoom, fit and camera angles"
        ) {
            Button("Zoom In", systemImage: "plus.magnifyingglass") {
                viewport.zoom(by: Self.zoomStep)
            }
            .keyboardShortcut(DS.Shortcuts.action(.zoomIn))

            Button("Zoom Out", systemImage: "minus.magnifyingglass") {
                viewport.zoom(by: 1 / Self.zoomStep)
            }
            .keyboardShortcut(DS.Shortcuts.action(.zoomOut))

            Divider()

            Button("Fit Model", systemImage: "arrow.down.right.and.arrow.up.left") {
                viewport.fit()
            }
            .keyboardShortcut(DS.Shortcuts.action(.fit))

            Divider()

            DSInlineMenuPicker("Camera", selection: preset) {
                ForEach(CameraPreset.allCases) { preset in
                    Label(preset.title, systemImage: preset.systemImage)
                        .tag(Optional(preset))
                        .keyboardShortcutIfAvailable(cameraPresetShortcut(for: preset))
                }
            }
        }
    }

    private var zoomLabel: String {
        "\(viewport.zoomPercent ?? 100)%"
    }

    private var preset: Binding<CameraPreset?> {
        Binding(
            get: { viewport.activeCameraPreset },
            set: { newValue in
                guard let newValue else { return }
                viewport.applyCameraPreset(newValue)
            }
        )
    }

    private func cameraPresetShortcut(for preset: CameraPreset) -> KeyboardShortcut? {
        DS.Shortcuts.CameraPreset(rawValue: preset.rawValue)
            .flatMap { DS.Shortcuts.cameraPreset($0) }
    }
}

// MARK: - Previews

#Preview("view menu", traits: .fixedLayout(width: 200, height: 64)) {
    PreviewCanvas(width: 200, height: 64, background: .canvas) {
        ViewMenu(viewport: MockViewportController())
    }
}
