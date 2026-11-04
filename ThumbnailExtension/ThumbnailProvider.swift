import Foundation
import GLTFCore
import QuickLookThumbnailing
import RendererWebKit

/// Finder thumbnail principal class. Renders through the same renderer the document window and
/// Quick Look use (`CanvasRenderer`), so a file's Finder icon matches how it opens. The render
/// itself is `ThumbnailRenderer` (RendererWebKit), which the tests drive in-process.
class ThumbnailProvider: QLThumbnailProvider {

    override func provideThumbnail(for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        let scale = max(request.scale, 1)
        let pixel = max(64, Int(max(request.maximumSize.width, request.maximumSize.height) * scale))
        let url = request.fileURL

        // Quick Look copies the image from the handed-off URL but never deletes it, and the
        // extension gets no completion callback — so clear PNGs left by earlier requests.
        Self.sweepStaleThumbnails()

        Task.detached {
            do {
                let fileURL = try await Self.render(url: url, pixel: pixel)
                // Finder's generator reliably consumes `imageFileURL`. The CGContext drawing
                // reply works under `qlmanage -x` but fails there with QLThumbnailError 102 —
                // do not "simplify" this to the drawing reply.
                handler(QLThumbnailReply(imageFileURL: fileURL), nil)
            } catch {
                AppLog.error(
                    AppLog.thumbnail,
                    "thumbnail failed \(url.lastPathComponent) \(error.localizedDescription)"
                )
                handler(nil, error)
            }
        }
    }

    /// One warm host per extension process, serialized.
    @MainActor
    private static let renderer = ThumbnailRenderer()

    /// PNG file for Quick Look to copy.
    @MainActor
    private static func render(url: URL, pixel: Int) async throws -> URL {
        let started = CFAbsoluteTimeGetCurrent()
        let result = try await renderer.render(url: url, pixel: pixel)

        let fileURL = outputURL()
        try result.markedPNG.write(to: fileURL)
        do {
            try FirstPixelPreview.store(png: result.png, for: url)
        } catch {
            AppLog.error(AppLog.webRenderer, "poster cache failed \(url.lastPathComponent): \(error.localizedDescription)")
        }

        AppLog.info(
            AppLog.webRenderer,
            String(
                format: "thumbnail ready %@ %.0fms %dpx %dB tris=%d renderer=%@",
                url.lastPathComponent, (CFAbsoluteTimeGetCurrent() - started) * 1000,
                pixel, result.png.count, result.info.triangles, result.rendererName
            )
        )
        return fileURL
    }

    private static let outputPrefix = "glb-thumb-"

    /// A fresh temp PNG path for one reply. `sweepStaleThumbnails` clears these later.
    static func outputURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(outputPrefix)\(UUID().uuidString).png")
    }

    /// Remove `glb-thumb-*.png` files older than a minute. Best-effort: the age guard keeps a
    /// concurrent request's just-written file from being deleted before Quick Look reads it.
    private static func sweepStaleThumbnails() {
        let tmp = FileManager.default.temporaryDirectory
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: tmp,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = Date(timeIntervalSinceNow: -60)
        for entry in entries
        where entry.lastPathComponent.hasPrefix(outputPrefix) && entry.pathExtension == "png" {
            let modified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            if let modified, modified < cutoff {
                try? FileManager.default.removeItem(at: entry)
            }
        }
    }
}
