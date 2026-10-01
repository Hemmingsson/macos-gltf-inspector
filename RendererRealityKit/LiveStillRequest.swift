import CoreGraphics
import RealityKit

/// Host PNG export: clone the turntable and re-render at the live camera pose.
@MainActor
public enum LiveStillRequest {
    /// `nil` when the canvas has no live camera pose yet.
    public static func renderLiveStill(
        interaction: PreviewInteraction,
        exposureEV: Float,
        dimStudioForFileLights: Bool,
        backdropIndex: Int,
        environmentYaw: Float,
        aspect: Float,
        pixelHeight: Int = 1080
    ) async throws -> CGImage? {
        guard let camera = interaction.camera,
              let pivot = interaction.orbitFocus,
              let pose = StillCameraPose.capturing(from: camera)
        else { return nil }
        return try await StillRenderer.renderImage(
            root: pivot.clone(recursive: true),
            cameraPose: pose,
            background: PreviewBackground.at(backdropIndex).stillBackgroundCGColor,
            intensityExponent: RealityLook.iblExponent(
                exposureEV: exposureEV,
                dimEV: RealityPolicy.studioDimEV(fileHasLights: dimStudioForFileLights)
            ),
            environmentYaw: environmentYaw,
            pixelHeight: pixelHeight,
            aspect: aspect
        )
    }
}
