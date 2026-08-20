import QuickLookThumbnailing
import RealityKit
import CoreGraphics

class ThumbnailProvider: QLThumbnailProvider {

    override func provideThumbnail(for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        let scale = max(request.scale, 1)
        let pixel = max(64, Int(max(request.maximumSize.width, request.maximumSize.height) * scale))
        let url = request.fileURL

        Task { @MainActor in
            do {
                let model = try await EntityLoader.load(from: url, includeAnimations: false)
                let assembled = PreviewCamera.makeTurntable(for: model.entity)
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
                try StillRenderer.writePNG(image, to: fileURL)
                // Finder / QLThumbnailGenerator reliably consumes imageFileURL.
                // The CGContext drawing reply works in `qlmanage -x` but fails with
                // QLThumbnailError 102 for the generator path Finder uses.
                handler(QLThumbnailReply(imageFileURL: fileURL), nil)
            } catch {
                AppLog.error(AppLog.thumbnail, "thumbnail failed \(url.path) \(error)")
                handler(nil, error)
            }
        }
    }
}
