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
        let result = SavePanelResult()
        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                result.install(continuation)
                guard !Task.isCancelled else {
                    result.resume(nil)
                    return
                }
                if let window = NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible) {
                    panel.beginSheetModal(for: window) { response in
                        result.resume(response == .OK ? panel.url : nil)
                    }
                } else {
                    result.resume(panel.runModal() == .OK ? panel.url : nil)
                }
            }
        }, onCancel: {
            result.resume(nil)
            Task { @MainActor in panel.cancel(nil) }
        })
    }

    /// A failed export: an alert sheet on the key window, or a modal alert
    /// when no window is available. The file that was there before is untouched.
    @MainActor
    static func reportFailure(title: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = "The export could not be completed. Check the destination and try again."
        if let window = NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible) {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private final class SavePanelResult: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<URL?, Never>?
        private var didResume = false

        func install(_ continuation: CheckedContinuation<URL?, Never>) {
            lock.lock()
            defer { lock.unlock() }
            guard !didResume else {
                continuation.resume(returning: nil)
                return
            }
            self.continuation = continuation
        }

        func resume(_ url: URL?) {
            lock.lock()
            defer { lock.unlock() }
            guard !didResume else { return }
            didResume = true
            continuation?.resume(returning: url)
            continuation = nil
        }
    }
}
