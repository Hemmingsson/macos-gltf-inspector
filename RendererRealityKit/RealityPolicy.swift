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

    /// Spec-gloss texture bake cost cap: bake only when the file has ≤ 40 images and ≤ 24
    /// textured spec-gloss materials; above that the materials use factor-only metal/rough
    /// (reported as "Converted from KHR spec-gloss" without "baked textures").
    static func bakesSpecGlossTextures(imageCount: Int, texturedMaterialCount: Int) -> Bool {
        imageCount <= 40 && texturedMaterialCount <= 24
    }

    enum BlendOverride: Equatable {
        case opaque
        case cutout(threshold: Float)
    }

    /// Sketchfab-style BLEND fixes, only when the factor alpha is 1 (a factor below 1 is real
    /// transparency and stays spec BLEND):
    /// - no texture, or texture alpha constant (0 = "car paint" exports, 1 = no alpha) → opaque
    ///   (reported `forcedOpaqueBlend`); with alpha 1 this is also the spec result, minus sorting;
    /// - texture alpha with a real span (≥ 0.15, foliage / decals) → cutout at 0.4 (reported
    ///   `blendAsCutout`). Also EXP-009 (KEEP): cheaper than blending full-resolution alpha.
    static func blendOverride(factorAlpha: Float, textureAlpha: TextureAlpha.Usage?) -> BlendOverride? {
        guard factorAlpha >= 0.999 else { return nil }
        return textureAlpha == .cutout ? .cutout(threshold: 0.4) : .opaque
    }
}
