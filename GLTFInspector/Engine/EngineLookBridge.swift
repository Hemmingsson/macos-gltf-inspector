import Foundation
import PreviewUI

/// Maps the seam's look vocabulary onto the web renderer's.
///
/// The mapping lives here, in the host, rather than in `Shared/`: `LightingSettings` is a
/// `PreviewUI` type and the Quick Look and thumbnail extensions do not link that framework.
extension WebPreviewCanvas.Look {
    init(_ lighting: LightingSettings) {
        self.init(
            environment: lighting.environment.rawValue,
            toneMapping: Self.khronosToneMap(lighting.toneMapping),
            exposure: lighting.exposure,
            environmentRotation: lighting.environmentRotationDegrees
        )
    }

    /// Values are `GltfState.ToneMaps` strings — the renderer matches on the string, so these
    /// have to stay exact.
    private static func khronosToneMap(_ toneMapping: ToneMapping) -> String {
        switch toneMapping {
        case .neutral: "Khronos PBR Neutral"
        case .acesHill: "ACES Filmic Tone Mapping (Hill)"
        case .acesNarkowicz: "ACES Filmic Tone Mapping (Narkowicz)"
        case .linear: "None (Linear mapping, clamped at 1.0)"
        }
    }
}
