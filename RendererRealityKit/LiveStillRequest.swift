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
        aspect: Float
    ) async throws -> CGImage? {
        guard let camera = interaction.camera,
              let pivot = interaction.orbitFocus,
              let pose = StillCameraPose.capturing(from: camera)
        else { return nil }
        let safeAspect = (aspect > 0.05 && aspect < 20) ? aspect : (16 / 9)
        let height = 1080
        let width = max(64, Int((Float(height) * safeAspect).rounded()))
        return try await StillRenderer.render(
            root: pivot.clone(recursive: true),
            cameraPose: pose,
            width: width,
            height: height,
            background: PreviewBackground.at(backdropIndex).stillBackgroundCGColor,
            intensityExponent: RealityLook.iblExponent(
                exposureEV: exposureEV,
                dimEV: RealityPolicy.studioDimEV(fileHasLights: dimStudioForFileLights)
            ),
            environmentYaw: environmentYaw
        )
    }
}
