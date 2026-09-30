import Foundation

/// Product heuristics that are not glTF spec. Convert maps the file as the spec says; these rules
/// sit on top, each one reported to the user (`PreparePipelineReport` entries / convert problems).
enum RealityPolicy {
    /// Studio IBL dim, in EV, when the file brings its own `KHR_lights_punctual` lights, so the
    /// studio does not wash them out. Reported as "File lights: on · Studio IBL: dimmed".
    static let fileLightStudioDimEV: Float = -2

    static func studioDimEV(fileHasLights: Bool) -> Float {
        fileHasLights ? fileLightStudioDimEV : 0
    }

    /// Load-time studio exponent (0 or the dim) for a converted entity's light count.
    static func studioIBLExponent(punctualLightCount: Int) -> Float {
        studioDimEV(fileHasLights: punctualLightCount > 0)
    }
}
