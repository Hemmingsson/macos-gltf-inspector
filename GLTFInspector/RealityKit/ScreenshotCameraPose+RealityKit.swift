import AppKit
import RendererRealityKit

extension ScreenshotCameraPose {
    enum Failure: LocalizedError {
        case noLiveCameraPose

        var errorDescription: String? { "no live camera pose" }
    }

    /// RealityKit canvas: an offscreen re-render at the live camera pose, not a RealityView
    /// framebuffer grab.
    @MainActor
    static func renderReality(
        interaction: PreviewInteraction,
        dimStudioForFileLights: Bool,
        exposureEV: Float,
        backdrop: String,
        environmentYaw: Float
    ) async throws -> CGImage {
        let aspect: Float = {
            if let view = NSApp.keyWindow?.contentView, view.bounds.height > 1 {
                return Float(view.bounds.width / view.bounds.height)
            }
            return 16 / 9
        }()
        guard let image = try await LiveStillRequest.renderLiveStill(
            interaction: interaction,
            exposureEV: exposureEV,
            dimStudioForFileLights: dimStudioForFileLights,
            backdropIndex: PreviewBackground.index(matchingRawValue: backdrop),
            environmentYaw: environmentYaw,
            aspect: aspect
        ) else {
            throw Failure.noLiveCameraPose
        }
        return image
    }
}
