import QuickLookThumbnailing
import RealityKit
import CoreGraphics

class ThumbnailProvider: QLThumbnailProvider {

    override func provideThumbnail(for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        let scale = max(request.scale, 1)
        let pixel = max(64, Int(max(request.maximumSize.width, request.maximumSize.height) * scale))
        let url = request.fileURL

        // Quick Look copies the image from the handed-off URL but never deletes it, and the
        // extension gets no completion callback — so clear PNGs left by earlier requests.
        Self.sweepStaleThumbnails()

        // Detached like Quick Look: prepare/parse off the main actor; RealityKit
        // convert and StillRenderer hop to MainActor inside EntityLoader / capture.
        Task.detached {
            do {
                let model = try await EntityLoader.loadThumbnail(from: url)
                let assembled = await PreviewCamera.makeTurntable(for: model.entity)
                let still = try await StillRenderer(
                    root: assembled.pivot,
                    bounds: assembled.bounds,
                    width: pixel,
                    height: pixel,
                    background: CGColor(gray: 0.94, alpha: 1),
                    padding: PreviewCamera.thumbnailFitPadding,
                    intensityExponent: model.studioIBLExponent
                )
                let image = try await still.capture()
                let fileURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("glb-thumb-\(UUID().uuidString).png")
                try await MainActor.run {
                    try StillRenderer.writePNG(image, to: fileURL)
                }
                // Finder / QLThumbnailGenerator reliably consumes imageFileURL.
                // The CGContext drawing reply works in `qlmanage -x` but fails with
                // QLThumbnailError 102 for the generator path Finder uses.
                handler(QLThumbnailReply(imageFileURL: fileURL), nil)
            } catch {
                AppLog.error(AppLog.thumbnail, "thumbnail failed \(url.lastPathComponent) \(error)")
                handler(nil, error)
            }
        }
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
        where entry.lastPathComponent.hasPrefix("glb-thumb-") && entry.pathExtension == "png" {
            let modified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            if let modified, modified < cutoff {
                try? FileManager.default.removeItem(at: entry)
            }
        }
    }
}
