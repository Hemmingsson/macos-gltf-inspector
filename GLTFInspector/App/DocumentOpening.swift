import AppKit
import GLTFCore
import SwiftUI
import UniformTypeIdentifiers

enum DocumentOpening {
    static func isGLTFFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "glb" || ext == "gltf"
    }

    /// Loads a file URL from drop providers and opens it via the document system.
    @discardableResult
    static func handleDrop(
        _ providers: [NSItemProvider],
        openDocument: OpenDocumentAction
    ) -> Bool {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else {
            return false
        }
        _ = provider.loadObject(ofClass: URL.self) { url, error in
            if let error {
                AppLog.error(AppLog.app, "drop URL load failed \(error)")
            }
            guard let url, isGLTFFile(url) else { return }
            Task { @MainActor in
                do {
                    try await openDocument(at: url)
                } catch {
                    AppLog.error(AppLog.app, "openDocument failed \(error.localizedDescription)")
                }
            }
        }
        return true
    }

    /// Puts the open file on the clipboard as a file URL, so Finder pastes a copy.
    static func copyFile(_ url: URL, pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
    }

    /// A glTF or GLB file URL currently on the given pasteboard.
    static func pastedGLTFURL(pasteboard: NSPasteboard = .general) -> URL? {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL]
        return urls?.first { isGLTFFile($0) }
    }

    /// Opens the glTF file on the clipboard, if there is one.
    @MainActor
    static func pasteGLTF() {
        guard let url = pastedGLTFURL() else { return }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error {
                AppLog.error(AppLog.app, "paste failed \(error.localizedDescription)")
            }
        }
    }

    static func closeWelcomeWindows() {
        for window in NSApp.windows where window.identifier?.rawValue == WelcomeWindow.id {
            window.close()
        }
    }
}

enum WelcomeWindow {
    static let id = "welcome"
}

@MainActor
private final class RecentMenuTarget: NSObject {
    static let shared = RecentMenuTarget()

    @objc func open(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error {
                AppLog.error(AppLog.app, "open recent failed \(error.localizedDescription)")
            }
        }
    }

    @objc func clear(_ sender: NSMenuItem) {
        NSDocumentController.shared.clearRecentDocuments(sender)
    }
}

enum RecentGLTFFiles {
    static let limit = 6

    /// The document controller's recent `.glb` / `.gltf` files, capped.
    @MainActor
    static func current() -> [URL] {
        urls(from: NSDocumentController.shared.recentDocumentURLs)
    }

    /// Pops the recent-files menu under the pointer. The system document controller opens the file.
    @MainActor
    static func popUpMenu() {
        let menu = NSMenu()
        let urls = current()
        if urls.isEmpty {
            let empty = NSMenuItem(title: "No Recent Files", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for url in urls {
                let item = NSMenuItem(
                    title: url.lastPathComponent,
                    action: #selector(RecentMenuTarget.open(_:)),
                    keyEquivalent: ""
                )
                item.target = RecentMenuTarget.shared
                item.representedObject = url
                item.toolTip = url.path
                menu.addItem(item)
            }
            menu.addItem(.separator())
            let clear = NSMenuItem(
                title: "Clear Menu",
                action: #selector(RecentMenuTarget.clear(_:)),
                keyEquivalent: ""
            )
            clear.target = RecentMenuTarget.shared
            menu.addItem(clear)
        }
        guard let view = NSApp.keyWindow?.contentView else {
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
            return
        }
        let point = view.convert(NSEvent.mouseLocation, from: nil)
        menu.popUp(positioning: nil, at: point, in: view)
    }

    /// The first `.glb` / `.gltf` URLs in `recent`, capped.
    static func urls(from recent: [URL]) -> [URL] {
        var kept: [URL] = []
        for url in recent where DocumentOpening.isGLTFFile(url) {
            kept.append(url)
            if kept.count == limit { break }
        }
        return kept
    }
}

/// Stub viewer document. `DocumentWindow` loads from `FileDocumentConfiguration.fileURL`.
struct GLTFInspectorFileDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [
            UTType(importedAs: "org.khronos.glb"),
            UTType(importedAs: "org.khronos.gltf"),
        ]
    }

    static var writableContentTypes: [UTType] { [] }

    init(configuration: ReadConfiguration) throws {
        // Intentionally ignore FileWrapper bytes — the renderer loads from the file URL, so sidecar
        // buffers and textures resolve against its folder.
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        throw CocoaError(.fileWriteNoPermission)
    }
}
