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
                let model = try await GLBEntityLoader.load(from: url, includeAnimations: false)
                let assembled = GLBPreviewCamera.makeTurntable(for: model.entity)
                let still = try await GLBStillRenderer(
                    root: assembled.pivot,
                    bounds: assembled.bounds,
                    width: pixel,
                    height: pixel,
                    background: CGColor(gray: 0.94, alpha: 1),
                    padding: GLBPreviewCamera.thumbnailFitPadding,
                    intensityExponent: model.studioIBLExponent
                )
                let image = try await still.capture()
                let fileURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("glb-thumb-\(UUID().uuidString).png")
                try GLBStillRenderer.writePNG(image, to: fileURL)
                // Finder / QLThumbnailGenerator reliably consumes imageFileURL.
                // The CGContext drawing reply works in `qlmanage -x` but fails with
                // QLThumbnailError 102 for the generator path Finder uses.
                handler(QLThumbnailReply(imageFileURL: fileURL), nil)
            } catch {
                GLBLog.error(GLBLog.thumbnail, "thumbnail failed \(url.path) \(error)")
                handler(nil, error)
            }
        }
    }
}
