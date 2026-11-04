import AppKit
import UniformTypeIdentifiers

/// The export save panel: a sheet on the key window so AX / Peekaboo can target it, `runModal`
/// only when no window is available. `nil` when cancelled.
enum SavePanel {
    @MainActor
    static func choose(_ type: UTType, name: String, title: String, message: String) async -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = name
        panel.title = title
        panel.message = message
        return await withCheckedContinuation { continuation in
            if let window = NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible) {
                panel.beginSheetModal(for: window) { continuation.resume(returning: $0 == .OK ? panel.url : nil) }
            } else {
                continuation.resume(returning: panel.runModal() == .OK ? panel.url : nil)
            }
        }
    }
}
