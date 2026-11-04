import Renderer
import SwiftUI

/// Zoom and Fit shared by the menu bar View menu and the canvas View menu.
struct ViewportZoomCommands: View {
    var view: ViewState

    var body: some View {
        Button("Zoom In", systemImage: "plus.magnifyingglass") { view.zoom(by: ViewState.zoomStep) }
            .keyboardShortcut(Shortcuts.action(.zoomIn))
        Button("Zoom Out", systemImage: "minus.magnifyingglass") { view.zoom(by: 1 / ViewState.zoomStep) }
            .keyboardShortcut(Shortcuts.action(.zoomOut))
        Button("Fit", systemImage: "viewfinder") { view.fit() }
            .keyboardShortcut(Shortcuts.action(.fit))
    }
}

struct ViewportCameraPresetCommands: View {
    var view: ViewState

    var body: some View {
        ForEach(CameraPreset.allCases) { preset in
            Button(preset.title, systemImage: preset.systemImage) { view.show(preset) }
                .keyboardShortcutIfAvailable(Shortcuts.cameraPreset(preset))
        }
    }
}
