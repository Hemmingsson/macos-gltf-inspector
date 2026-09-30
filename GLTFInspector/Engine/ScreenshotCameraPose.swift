import AppKit
import GLTFCore
import RendererRealityKit
import UniformTypeIdentifiers

/// Offscreen PNG export at the live camera pose (not a RealityView framebuffer grab).
/// Extracted so `EngineViewportController.screenshot()` can share the export path.
///
/// The renderer only returns pixels; the save panel and the file write stay in the host.
enum ScreenshotCameraPose {
    /// Samples the live camera, presents the save panel, then re-renders and writes the PNG.
    @MainActor
    static func capture(
        interaction: PreviewInteraction,
        dimStudioForFileLights: Bool,
        exposureEV: Float,
        backdropIndex: Int,
        environmentYaw: Float,
        suggestedName: String
    ) {
        Task { @MainActor in
            guard let request = LiveStillRequest(
                interaction: interaction,
                dimStudioForFileLights: dimStudioForFileLights,
                exposureEV: exposureEV,
                backdropIndex: backdropIndex,
                environmentYaw: environmentYaw
            ) else {
                AppLog.error(AppLog.host, "PNG export skipped — no live camera pose")
                return
            }
            let aspect: Float = {
                if let view = NSApp.keyWindow?.contentView, view.bounds.height > 1 {
                    return Float(view.bounds.width / view.bounds.height)
                }
                return 16 / 9
            }()
            do {
                guard let url = await chooseDestination(suggestedName: suggestedName) else { return }
                let image = try await request.render(aspect: aspect)
                try PNGWriter.write(image, to: url)
                AppLog.info(
                    AppLog.host,
                    "PNG export wrote \(url.path) (offscreen re-render at live camera pose)"
                )
            } catch {
                AppLog.error(AppLog.host, "PNG export failed: \(error.localizedDescription)")
            }
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
        panel.message = "Offscreen PNG re-render at the current camera pose."

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
