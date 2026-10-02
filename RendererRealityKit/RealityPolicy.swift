import Foundation
import GLTFKit2
import simd

/// Product heuristics that are not glTF spec. Convert maps the file as the spec says; these rules
/// sit on top, each one reported to the user (`RealityPipelineReport` entries / convert problems).
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

    // MARK: - Baked emissive

    /// Sketchfab / 3ds Max often write `emissiveFactor: [1,1,1]` (and a copy of the albedo as
    /// `emissiveTexture`) so the mesh is visible in a dark viewer. With the studio IBL that is a
    /// second full-bright light that washes the model out, so emissive is dropped when it copies
    /// the albedo texture, or when most of the file's materials carry such an achromatic boost.
    /// Strength > 1 (`KHR_materials_emissive_strength`) is intentional glow and always kept.
    /// Reported per material (`droppedEmissive`) and in the pipeline report.
    struct EmissiveHint: Equatable {
        var factor: SIMD3<Float> = .zero
        var strength: Float = 1
        var hasTexture: Bool = false
        var sharesAlbedoTexture: Bool = false

        var hasEmissive: Bool {
            hasTexture || max(factor.x, max(factor.y, factor.z)) > 0.01
        }

        /// Gray/white boost, not a colored neon.
        var isAchromaticBoost: Bool {
            guard hasEmissive, strength <= 1.001 else { return false }
            let maxC = max(factor.x, max(factor.y, factor.z))
            let minC = min(factor.x, min(factor.y, factor.z))
            return maxC - minC < 0.08
        }

        init(factor: SIMD3<Float> = .zero, strength: Float = 1, hasTexture: Bool = false, sharesAlbedoTexture: Bool = false) {
            self.factor = factor
            self.strength = strength
            self.hasTexture = hasTexture
            self.sharesAlbedoTexture = sharesAlbedoTexture
        }

        init(_ material: GLTFMaterial) {
            let emissive = material.emissive
            let albedoTexture = material.metallicRoughness?.baseColorTexture?.texture
                ?? material.specularGlossiness?.diffuseTexture?.texture
            let emissiveTexture = emissive?.emissiveTexture?.texture
            self.init(
                factor: emissive?.emissiveFactor ?? .zero,
                strength: emissive?.emissiveStrength ?? 1,
                hasTexture: emissiveTexture != nil,
                sharesAlbedoTexture: albedoTexture != nil && albedoTexture === emissiveTexture
            )
        }
    }

    /// Most materials use emissive as baked lighting, not as a few glow parts.
    static func fileLooksBaked(_ hints: [EmissiveHint]) -> Bool {
        let junk = hints.filter(\.isAchromaticBoost)
        return !junk.isEmpty && junk.count * 2 >= hints.count
    }

    static func dropsEmissive(_ hint: EmissiveHint, fileLooksBaked: Bool) -> Bool {
        if hint.strength > 1.001 { return false }
        if hint.sharesAlbedoTexture { return true }
        return fileLooksBaked && hint.isAchromaticBoost
    }
}
