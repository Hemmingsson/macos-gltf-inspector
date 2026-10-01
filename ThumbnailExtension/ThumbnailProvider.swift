import CoreGraphics
import Foundation
import GLTFCore
import QuickLookThumbnailing

/// Finder thumbnail principal class and the extension's one renderer router: reads the renderer
/// switch per request and renders through `ThumbnailRealityKit.swift` or `ThumbnailWebKit.swift`.
/// Each case is guarded by `canImport`, so removing a renderer needs no edit here.
class ThumbnailProvider: QLThumbnailProvider {

    override func provideThumbnail(for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        let scale = max(request.scale, 1)
        let pixel = max(64, Int(max(request.maximumSize.width, request.maximumSize.height) * scale))
        let url = request.fileURL

        // Quick Look copies the image from the handed-off URL but never deletes it, and the
        // extension gets no completion callback — so clear PNGs left by earlier requests.
        Self.sweepStaleThumbnails()

        let kind = RendererKind.stored()
        Task.detached {
            do {
                let fileURL = try await Self.render(url: url, pixel: pixel, kind: kind)
                // Finder's generator reliably consumes `imageFileURL`. The CGContext drawing
                // reply works under `qlmanage -x` but fails there with QLThumbnailError 102 —
                // do not "simplify" this to the drawing reply.
                handler(QLThumbnailReply(imageFileURL: fileURL), nil)
            } catch {
                AppLog.error(
                    AppLog.thumbnail,
                    "thumbnail failed \(kind.rawValue) \(url.lastPathComponent) \(error.localizedDescription)"
                )
                handler(nil, error)
            }
        }
    }

    /// PNG file for Quick Look to copy.
    private static func render(url: URL, pixel: Int, kind: RendererKind) async throws -> URL {
        #if canImport(RendererWebKit)
        if kind == .webKit { return try await WebThumbnail.render(url: url, pixel: pixel) }
        #endif
        #if canImport(RendererRealityKit)
        return try await RealityKitThumbnail.render(url: url, pixel: pixel)
        #else
        return try await WebThumbnail.render(url: url, pixel: pixel)
        #endif
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
