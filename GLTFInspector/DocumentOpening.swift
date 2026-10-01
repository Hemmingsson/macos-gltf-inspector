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
                AppLog.error(AppLog.host, "drop URL load failed \(error)")
            }
            guard let url, isGLTFFile(url) else { return }
            Task { @MainActor in
                do {
                    try await openDocument(at: url)
                } catch {
                    AppLog.error(AppLog.host, "openDocument failed \(error.localizedDescription)")
                }
            }
        }
        return true
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
