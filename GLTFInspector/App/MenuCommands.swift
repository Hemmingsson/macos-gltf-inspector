import AppKit
import SwiftUI
import Renderer

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

/// View ▸ Toggle Sidebar (⌘B), the only way to show or hide the sidebar. Sent up the responder
/// chain to the window's split view, which keeps `NavigationSplitView`'s column visibility.
struct ToggleSidebarCommand: View {
    var body: some View {
        Button("Toggle Sidebar") {
            NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
        }
        .keyboardShortcut(Shortcuts.action(.toggleSidebar))
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

/// The menu bar's View menu items for the key document window: the full command set, with the
/// same shortcuts as the canvas controls.
///
/// Lives in `CommandGroup(after: .sidebar)`, never `CommandMenu("View")`. Sidebar visibility is
/// `ToggleSidebarCommand` (⌘B).
struct ViewMenuCommands: View {
    @FocusedValue(\.documentWindow) private var window

    var body: some View {
        if let view = window?.view {
            ViewMenuItems(view: view)
        } else {
            Text("No focused window")
                .disabled(true)
        }
    }
}

private struct ViewMenuItems: View {
    @Bindable var view: ViewState

    var body: some View {
        Picker("View Mode", selection: $view.viewMode) {
            ForEach(view.viewModes.filter { $0 == .shaded || $0 == .wireframe }, id: \.self) { mode in
                Text(mode.title)
                    .tag(mode)
                    .keyboardShortcutIfAvailable(Shortcuts.viewMode(mode))
            }
        }

        Picker("Backdrop", selection: $view.backdrop) {
            ForEach(BackdropStyle.allCases) { style in
                Text(style.title).tag(style)
            }
        }

        Toggle("Show Floor", systemImage: "circle.grid.cross", isOn: $view.showsFloor)

        Toggle("Auto-Rotate", systemImage: "arrow.trianglehead.counterclockwise.rotate.90", isOn: $view.autoRotates)
            .keyboardShortcut(Shortcuts.action(.autoRotate))

        Toggle("Center Model", systemImage: "dot.scope", isOn: $view.isCentered)
            .keyboardShortcut(Shortcuts.action(.center))

        Toggle("Orthographic", systemImage: "perspective", isOn: $view.isOrthographic)
            .keyboardShortcut(Shortcuts.action(.orthographic))

        Divider()

        Group {
            ViewportZoomCommands(view: view)
        }
        .disabled(view.canvas.phase != .ready)

        Button("Reset View", systemImage: "arrow.counterclockwise") { view.resetView() }
            .keyboardShortcut(Shortcuts.action(.reset))

        Divider()

        ViewportCameraPresetCommands(view: view)
            .disabled(view.canvas.phase != .ready)
    }
}
