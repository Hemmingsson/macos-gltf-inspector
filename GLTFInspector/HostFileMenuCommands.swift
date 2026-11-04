import AppKit
import PreviewUI
import SwiftUI

/// Host File menu: a plain New Window (the app never creates documents).
struct NewWindowCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("New Window") {
            openWindow(id: WelcomeWindow.id)
        }
        .keyboardShortcut("n", modifiers: [.command])
    }
}

/// Host File menu: the `.saveItem` group without Save, Save As and Duplicate. Rename and Move To
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

/// Host File menu: export a PNG still for the focused document window. Dimmed, not hidden, when
/// no document window has focus (HIG: keep unavailable menu items visible).
struct HostFileMenuCommands: View {
    @FocusedValue(\.engineViewport) private var viewport

    var body: some View {
        Button("Export PNG…", systemImage: "camera") {
            viewport?.screenshot()
        }
        .keyboardShortcut("e", modifiers: [.command])
        .disabled(viewport?.commands == nil)
    }
}

extension FocusedValues {
    /// The focused document window's file, for Share. Nil in an empty window.
    @Entry var documentFileURL: URL?
}
