import CoreGraphics
import Foundation

/// Finder icon through RealityKit: convert without clips, front-¾ turntable framing, one offscreen
/// `StillRenderer` frame on the light-grey thumbnail backdrop.
public enum RealityThumbnail {
    /// Texture cap for icons: measured −8 % icon wall time on the load corpus, all of it on
    /// files with 2K–4K textures (seam 11 step 10).
    static let maxTextureEdge = 1024

    public static func render(url: URL, pixel: Int) async throws -> CGImage {
        let model = try await EntityLoader.loadThumbnail(from: url, maxTextureEdge: maxTextureEdge)
        let assembled = await PreviewCamera.makeTurntable(for: model.entity)
        return try await StillRenderer.render(
            root: assembled.pivot,
            bounds: assembled.bounds,
            width: pixel,
            height: pixel,
            background: CGColor(gray: 0.94, alpha: 1),
            padding: PreviewCamera.thumbnailFitPadding,
            intensityExponent: model.studioIBLExponent
        )
    }
}
