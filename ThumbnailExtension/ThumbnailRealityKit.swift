import Foundation
import GLTFCore
import RendererRealityKit

/// Finder icons on the RealityKit renderer (as `main` ships them): convert without clips, one
/// offscreen `StillRenderer` frame (`RealityThumbnail`). Detached like Quick Look: prepare /
/// parse run off the main actor; convert and the still hop to it inside the framework.
enum RealityKitThumbnail {
    static func render(url: URL, pixel: Int) async throws -> URL {
        let started = CFAbsoluteTimeGetCurrent()
        let image = try await RealityThumbnail.render(url: url, pixel: pixel)
        let fileURL = ThumbnailProvider.outputURL()
        try PNGWriter.write(image, to: fileURL)
        do {
            try FirstPixelPreview.store(image: image, for: url, renderer: .realityKit)
        } catch {
            AppLog.error(AppLog.thumbnail, "poster cache failed \(url.lastPathComponent): \(error.localizedDescription)")
        }
        AppLog.info(
            AppLog.thumbnail,
            String(
                format: "thumbnail ready realitykit %@ %.0fms %dpx",
                url.lastPathComponent, (CFAbsoluteTimeGetCurrent() - started) * 1000, image.width
            )
        )
        return fileURL
    }
}
