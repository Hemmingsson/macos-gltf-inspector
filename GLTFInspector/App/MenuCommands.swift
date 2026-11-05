import AppKit
import GLTFCore
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

        TurntableExportButtons(view: window?.view, suggestedName: window?.exportName ?? "export")
        CopyGLBButton(url: window?.documentURL)
    }
}

/// File ▸ Export and the canvas Share menu: the open file, as a Finder-pasteable URL.
struct CopyGLBButton: View {
    var url: URL?

    var body: some View {
        Button("Copy GLB", systemImage: "doc.on.doc") {
            guard let url else { return }
            DocumentOpening.copyFile(url)
        }
        .disabled(url == nil)
    }
}

/// Export Turntable Video / GIF: the File menu and the canvas Share menu.
struct TurntableExportButtons: View {
    var view: ViewState?
    var suggestedName: String

    var body: some View {
        ForEach(TurntableExport.Format.allCases) { format in
            Button(format.menuTitle, systemImage: format == .mp4 ? "video" : "photo.stack") {
                view?.exportTurntable(format, suggestedName: suggestedName)
            }
            .disabled(view?.canvas.phase != .ready || view?.isExportingTurntable == true)
        }
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
            ViewMenuItems(view: view, document: window?.document ?? GLTFDocument())
        } else {
            Text("No focused window")
                .disabled(true)
        }
    }
}

/// Edit menu: hierarchy selection for the key document window.
struct SelectionMenuCommands: View {
    @FocusedValue(\.documentWindow) private var window

    var body: some View {
        let view = window?.view
        Button("Select All") { view?.selectAll() }
            .keyboardShortcut("a", modifiers: .command)
            .disabled(view == nil)
        Button("Select Parent") { view?.selectParent() }
            .keyboardShortcut(Shortcuts.action(.selectParent))
            .disabled(view?.canSelectParent != true)
        Button("Select Children") { view?.selectChildren() }
            .keyboardShortcut(Shortcuts.action(.selectChildren))
            .disabled(view?.canSelectChildren != true)
    }
}

private struct ViewMenuItems: View {
    @Bindable var view: ViewState
    var document: GLTFDocument

    private var hasSceneGizmos: Bool {
        !document.cameras.isEmpty || !document.lights.isEmpty
    }

    var body: some View {
        Picker("View Mode", selection: $view.viewMode) {
            ForEach(view.viewModes.filter { $0 == .shaded || RenderViewMode.displayModes.contains($0) }, id: \.self) { mode in
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

        if hasSceneGizmos {
            Toggle("Show Cameras & Lights", systemImage: "camera.viewfinder", isOn: $view.showsSceneGizmos)
        }

        Toggle("Auto-Rotate", systemImage: "arrow.trianglehead.counterclockwise.rotate.90", isOn: $view.autoRotates)
            .keyboardShortcut(Shortcuts.action(.autoRotate))

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

        Divider()

        // Layers act on every selected scene node; the outliner's eye and context menu act on one.
        let nodes = view.selectedSceneNodes
        Button(view.selectionIsHidden ? "Show Selection" : "Hide Selection") {
            view.toggleHiddenSelection()
        }
        .keyboardShortcut(Shortcuts.action(.hideSelection))
        .disabled(nodes.isEmpty)

        Button(view.selectionIsSoloed ? "Unsolo Selection" : "Solo Selection") {
            view.toggleSoloSelection()
        }
        .keyboardShortcut(Shortcuts.action(.soloSelection))
        .disabled(nodes.isEmpty)

        Button("Show All Layers") { view.showAll() }
            .disabled(view.hiddenNodes.isEmpty && view.soloNodes.isEmpty)
    }
}
