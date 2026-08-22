import SwiftUI

/// Host File menu: export a PNG still for the focused document window.
struct HostFileMenuCommands: View {
    @FocusedValue(\.engineViewport) private var viewport
    @FocusedValue(\.previewCommands) private var previewCommands

    var body: some View {
        if let viewport {
            HostFileMenuBody(viewport: viewport, previewCommands: previewCommands)
        } else {
            Text("No focused window")
                .disabled(true)
        }
    }
}

private struct HostFileMenuBody: View {
    @Bindable var viewport: EngineViewportController
    var previewCommands: FocusedPreviewCommands?

    var body: some View {
        Button("Export PNG…", systemImage: "camera") {
            viewport.screenshot()
        }
        .keyboardShortcut("e", modifiers: [.command])
        .disabled(previewCommands == nil)
    }
}
