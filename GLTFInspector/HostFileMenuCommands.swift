import AppKit
import PreviewUI
import SwiftUI

/// Host File menu: a plain New Window (the app never creates documents).
struct NewWindowCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("New Window", systemImage: MenuSymbol.newWindow) {
            openWindow(id: WelcomeWindow.id)
        }
        .keyboardShortcut("n", modifiers: [.command])
        .menuBarIcons()
    }
}

/// Host File menu: the `.saveItem` group without Save, Save As and Duplicate. Rename and Move To
/// go to the focused window's `NSDocument` through the responder chain.
struct DocumentFileCommands: View {
    @FocusedValue(\.documentFileURL) private var documentURL

    var body: some View {
        Button("Close", systemImage: MenuSymbol.close) {
            NSApp.sendAction(#selector(NSWindow.performClose(_:)), to: nil, from: nil)
        }
        .keyboardShortcut("w", modifiers: [.command])
        .menuBarIcons()

        Divider()

        Button("Rename…", systemImage: MenuSymbol.rename) {
            NSApp.sendAction(#selector(NSDocument.rename(_:)), to: nil, from: nil)
        }
        .disabled(documentURL == nil)
        .menuBarIcons()

        Button("Move To…", systemImage: MenuSymbol.moveTo) {
            NSApp.sendAction(#selector(NSDocument.move(_:)), to: nil, from: nil)
        }
        .disabled(documentURL == nil)
        .menuBarIcons()

        Divider()

        if let documentURL {
            ShareLink(item: documentURL) {
                Label("Share", systemImage: MenuSymbol.share)
            }
            .menuBarIcons()
        } else {
            Button("Share", systemImage: MenuSymbol.share) {}
                .disabled(true)
                .menuBarIcons()
        }
    }
}

/// Host File menu: export a PNG still for the focused document window. Dimmed, not hidden, when
/// no document window has focus (HIG: keep unavailable menu items visible).
struct HostFileMenuCommands: View {
    @FocusedValue(\.engineViewport) private var viewport

    var body: some View {
        Button("Export PNG…", systemImage: MenuSymbol.exportPNG) {
            viewport?.screenshot()
        }
        .keyboardShortcut("e", modifiers: [.command])
        .disabled(viewport?.commands == nil)
        .menuBarIcons()
    }
}

extension FocusedValues {
    /// The focused document window's file, for Share. Nil in an empty window.
    @Entry var documentFileURL: URL?
}
