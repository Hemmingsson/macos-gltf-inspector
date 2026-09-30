import AppKit
import GLTFCore
import UniformTypeIdentifiers

/// PNG export for the focused window. The mounted canvas's `FocusedPreviewCommands.screenshot`
/// supplies the pixels; this type owns the save panel and the file write. The RealityKit
/// re-render lives in `RealityKit/ScreenshotCameraPose+RealityKit.swift`.
enum ScreenshotCameraPose {
    /// Presents the save panel, then writes `image` as PNG. Cancel writes nothing.
    @MainActor
    static func save(_ image: CGImage, suggestedName: String) async {
        guard let url = await chooseDestination(suggestedName: suggestedName) else { return }
        do {
            try PNGWriter.write(image, to: url)
            AppLog.info(AppLog.host, "PNG export wrote \(url.lastPathComponent) \(image.width)x\(image.height)")
        } catch {
            AppLog.error(AppLog.host, "PNG export failed: \(error.localizedDescription)")
        }
    }

    /// Save panel as a sheet on the key window so AX / Peekaboo can target it; `runModal` only
    /// when no window is available. `nil` when cancelled.
    @MainActor
    private static func chooseDestination(suggestedName: String) async -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = suggestedName.hasSuffix(".png") ? suggestedName : "\(suggestedName).png"
        panel.title = "Export PNG"
        panel.message = "PNG of the canvas at the current camera pose."

        return await withCheckedContinuation { cont in
            if let window = NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible) {
                panel.beginSheetModal(for: window) { response in
                    cont.resume(returning: response == .OK ? panel.url : nil)
                }
            } else {
                let response = panel.runModal()
                cont.resume(returning: response == .OK ? panel.url : nil)
            }
        }
    }
}
