import AppKit
import GLTFCore
import UniformTypeIdentifiers

/// File ▸ Export PNG: `ViewState.exportPNG` supplies the canvas pixels; this owns the save panel
/// and the file write.
enum PNGExport {
    /// Presents the save panel, then writes `image` as PNG. Cancel writes nothing.
    @MainActor
    static func save(_ image: CGImage, suggestedName: String) async {
        let name = suggestedName.hasSuffix(".png") ? suggestedName : "\(suggestedName).png"
        guard let url = await SavePanel.choose(.png, name: name, title: "Export PNG",
                                               message: "PNG of the canvas at the current camera pose.") else { return }
        // Written beside the destination, then moved over it: a failed write leaves the old file.
        let temp = url.appendingPathExtension("tmp-\(UUID().uuidString)")
        do {
            do {
                try PNGWriter.write(image, to: temp)
                try AtomicFile.replace(url, with: temp)
            } catch {
                try? FileManager.default.removeItem(at: temp)
                throw error
            }
            AppLog.info(AppLog.app, "PNG export wrote \(url.lastPathComponent) \(image.width)x\(image.height)")
        } catch {
            AppLog.error(AppLog.app, "PNG export failed: \(error.localizedDescription)")
            SavePanel.reportFailure(title: "PNG export failed", error: error)
        }
    }
}
