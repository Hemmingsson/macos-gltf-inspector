import CoreGraphics
import Foundation

/// Finder icon through RealityKit: convert without clips, front-¾ turntable framing, one offscreen
/// `StillRenderer` frame on the light-grey thumbnail backdrop.
public enum RealityThumbnail {
    public static func render(url: URL, pixel: Int) async throws -> CGImage {
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
        return try await still.capture()
    }
}
