import PreviewUI
import SwiftUI

/// Host File menu: export a PNG still for the focused document window.
struct HostFileMenuCommands: View {
    @FocusedValue(\.engineViewport) private var viewport

    var body: some View {
        if let viewport {
            Button("Export PNG…", systemImage: "camera") {
                viewport.screenshot()
            }
            .keyboardShortcut("e", modifiers: [.command])
            .disabled(viewport.commands == nil)
        } else {
            Text("No focused window")
                .disabled(true)
        }
    }
}
