import Foundation
import PreviewUI

/// Maps the seam's look vocabulary onto the web renderer's.
///
/// The mapping lives here, in the host, rather than in `Shared/`: `LightingSettings` is a
/// `PreviewUI` type and the Quick Look and thumbnail extensions do not link that framework.
extension WebPreviewCanvas.Look {
    @MainActor
    init(_ viewport: some ViewportController, sceneIndex: Int) {
        let lighting = viewport.lighting
        self.init(
            environment: lighting.environment.rawValue,
            toneMapping: lighting.toneMapping.khronosName,
            exposure: lighting.exposure,
            environmentRotation: lighting.environmentRotationDegrees,
            backdrop: Self.clearColor(viewport.backdrop),
            autoRotates: viewport.autoRotates,
            projection: viewport.projection == .orthographic ? "orthographic" : "perspective",
            fieldOfView: Double(viewport.fieldOfViewDegrees),
            debugChannel: Self.khronosDebugChannel(viewport.viewMode),
            fileCameraIndex: nil,
            materialVariantIndex: viewport.selectedMaterialVariantIndex,
            sceneIndex: sceneIndex
        )
    }

    /// Alpha 0 for `window`, so the host window's own material shows through rather than the
    /// renderer painting a near-match over it.
    private static func clearColor(_ backdrop: BackdropStyle) -> [Double] {
        switch backdrop {
        case .window: [0, 0, 0, 0]
        case .white: [1, 1, 1, 1]
        case .dark: [0.09, 0.09, 0.10, 1]
        }
    }

    /// Values are `GltfState.DebugOutput` strings — matched by string, so they must stay exact.
    ///
    /// `wireframe` has no counterpart: the Khronos renderer has no wireframe mode. It falls back
    /// to shaded rather than showing an unrelated channel, and the gap is recorded rather than
    /// disguised.
    private static func khronosDebugChannel(_ mode: ViewMode) -> String {
        switch mode {
        case .shaded, .wireframe: "None"
        case .channel(let channel):
            switch channel {
            case .baseColor: "Base Color"
            case .metallic: "Metallic"
            case .roughness: "Roughness"
            case .normals: "Normal Texture"
            case .tangents: "Geometry Tangent"
            case .textureCoordinates: "Texture Coordinates 0"
            case .ambientOcclusion: "Occlusion"
            case .emissive: "Emissive"
            case .alpha: "Alpha"
            case .specular: "Specular Strength"
            case .clearcoat: "ClearCoat Strength"
            case .clearcoatRoughness: "ClearCoat Roughness"
            case .clearcoatNormal: "ClearCoat Normal"
            }
        }
    }

    /// Values are `GltfState.ToneMaps` strings — the renderer matches on the string, so these
    /// have to stay exact.
}
