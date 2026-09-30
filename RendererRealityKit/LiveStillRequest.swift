import CoreGraphics
import RealityKit

/// Host PNG export: the live camera pose and a clone of the turntable, taken before the save
/// panel opens so the export matches what was on screen. The host owns the panel and the file.
@MainActor
public struct LiveStillRequest {
    let root: Entity
    let cameraPose: StillCameraPose
    let background: CGColor
    let intensityExponent: Float
    let environmentYaw: Float

    /// `nil` when the canvas has no live camera pose yet.
    public init?(
        interaction: PreviewInteraction,
        dimStudioForFileLights: Bool,
        exposureEV: Float,
        backdropIndex: Int,
        environmentYaw: Float
    ) {
        guard let camera = interaction.camera,
              let pivot = interaction.orbitFocus,
              let pose = StillCameraPose.capturing(from: camera)
        else { return nil }
        root = pivot.clone(recursive: true)
        cameraPose = pose
        background = PreviewBackground.at(backdropIndex).stillBackgroundCGColor
        intensityExponent = RealityLook.iblExponent(
            exposureEV: exposureEV,
            dimEV: RealityPolicy.studioDimEV(fileHasLights: dimStudioForFileLights)
        )
        self.environmentYaw = environmentYaw
    }

    public func render(pixelHeight: Int = 1080, aspect: Float) async throws -> CGImage {
        try await StillRenderer.renderImage(
            root: root,
            cameraPose: cameraPose,
            background: background,
            intensityExponent: intensityExponent,
            environmentYaw: environmentYaw,
            pixelHeight: pixelHeight,
            aspect: aspect
        )
    }
}
