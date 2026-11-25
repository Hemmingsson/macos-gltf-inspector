import Renderer
import SwiftUI

/// Zoom and Fit shared by the menu bar View menu and the canvas View menu.
struct ViewportZoomCommands: View {
    var view: ViewState

    var body: some View {
        Button { view.zoom(by: ViewState.zoomStep) } label: { DSLabel("Zoom In", DSGlyphs.zoomIn) }
            .keyboardShortcut(Shortcuts.action(.zoomIn))
        Button { view.zoom(by: 1 / ViewState.zoomStep) } label: { DSLabel("Zoom Out", DSGlyphs.zoomOut) }
            .keyboardShortcut(Shortcuts.action(.zoomOut))
        Button { view.fit() } label: { DSLabel("Fit", DSGlyphs.fit) }
            .keyboardShortcut(Shortcuts.action(.fit))
        Button { view.frameSelection() } label: { DSLabel("Frame Selection", DSGlyphs.frameSelection) }
            .keyboardShortcut(Shortcuts.action(.frameSelection))
            .disabled(view.selectedSceneNodes.isEmpty)
    }
}

struct ViewportCameraPresetCommands: View {
    var view: ViewState

    var body: some View {
        ForEach(CameraPreset.allCases) { preset in
            Button { view.show(preset) } label: { DSLabel(preset.title, preset.glyph) }
                .keyboardShortcutIfAvailable(Shortcuts.cameraPreset(preset))
        }
    }
}
