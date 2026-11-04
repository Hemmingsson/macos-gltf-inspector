import AppKit
import SwiftUI

/// File ▸ New Window (the app never creates documents).
struct NewWindowCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("New Window") {
            openWindow(id: WelcomeWindow.id)
        }
        .keyboardShortcut("n", modifiers: [.command])
    }
}

/// File menu: the `.saveItem` group without Save, Save As and Duplicate. Rename and Move To
/// go to the focused window's `NSDocument` through the responder chain.
struct DocumentFileCommands: View {
    @FocusedValue(\.documentFileURL) private var documentURL

    var body: some View {
        Button("Close") {
            NSApp.sendAction(#selector(NSWindow.performClose(_:)), to: nil, from: nil)
        }
        .keyboardShortcut("w", modifiers: [.command])

        Divider()

        Button("Rename…") {
            NSApp.sendAction(#selector(NSDocument.rename(_:)), to: nil, from: nil)
        }
        .disabled(documentURL == nil)

        Button("Move To…") {
            NSApp.sendAction(#selector(NSDocument.move(_:)), to: nil, from: nil)
        }
        .disabled(documentURL == nil)

        Divider()

        if let documentURL {
            ShareLink("Share", item: documentURL)
        } else {
            Button("Share") {}
                .disabled(true)
        }
    }
}

/// File ▸ Export PNG for the key document window. Dimmed, not hidden, when no window can export
/// (HIG: keep unavailable menu items visible).
struct ExportPNGCommand: View {
    @FocusedValue(\.documentWindow) private var window

    var body: some View {
        Button("Export PNG…", systemImage: "camera") {
            guard let window else { return }
            window.view.exportPNG(suggestedName: window.exportName)
        }
        .keyboardShortcut("e", modifiers: [.command])
        .disabled(window?.view.canvas.phase != .ready)
    }
}
