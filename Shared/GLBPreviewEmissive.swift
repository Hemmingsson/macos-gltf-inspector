import Foundation
import GLTFKit2
import simd

/// Sketchfab / 3ds Max often write `emissiveFactor: [1,1,1]` (and a copy of the
/// albedo as `emissiveTexture`) so the mesh is visible in a dark viewer. With
/// studio IBL that becomes a second full-bright light and washes the model out.
enum GLBPreviewEmissive {
    struct Hint: Equatable {
        var factor: SIMD3<Float> = .zero
        var strength: Float = 1
        var hasTexture: Bool = false
        var sharesAlbedoTexture: Bool = false

        var hasEmissive: Bool {
            hasTexture || max(factor.x, max(factor.y, factor.z)) > 0.01
        }

        /// Gray/white boost, not a colored neon. Strength > 1 is intentional HDR glow.
        var isAchromaticBoost: Bool {
            guard hasEmissive, strength <= 1.001 else { return false }
            let maxC = max(factor.x, max(factor.y, factor.z))
            let minC = min(factor.x, min(factor.y, factor.z))
            return maxC - minC < 0.08
        }
    }

    static func hint(from material: GLTFMaterial) -> Hint {
        let emissive = material.emissive
        let albedoTexture = material.metallicRoughness?.baseColorTexture?.texture
            ?? material.specularGlossiness?.diffuseTexture?.texture
        let emissiveTexture = emissive?.emissiveTexture?.texture
        return Hint(
            factor: emissive?.emissiveFactor ?? .zero,
            strength: emissive?.emissiveStrength ?? 1,
            hasTexture: emissiveTexture != nil,
            sharesAlbedoTexture: albedoTexture != nil && albedoTexture === emissiveTexture
        )
    }

    /// Most materials are using emissive as baked lighting, not as a few glow parts.
    static func fileLooksBaked(_ hints: [Hint]) -> Bool {
        let junk = hints.filter(\.isAchromaticBoost)
        return !junk.isEmpty && junk.count * 2 >= hints.count
    }

    static func shouldIgnore(_ hint: Hint, fileLooksBaked: Bool) -> Bool {
        if hint.strength > 1.001 { return false }
        if hint.sharesAlbedoTexture { return true }
        return fileLooksBaked && hint.isAchromaticBoost
    }

    static func fileLooksBaked(json: [String: Any]) -> Bool {
        let materials = json["materials"] as? [[String: Any]] ?? []
        return fileLooksBaked(materials.map(hint(fromJSON:)))
    }

    /// Same studio probe as every other file. Only dim when the glTF authored
    /// punctual lights (they stack with IBL). Do not dim for baked-emissive files.
    static func studioIBLExponent(punctualLightCount: Int, fileLooksBaked: Bool = false) -> Float {
        _ = fileLooksBaked
        return punctualLightCount > 0 ? -2 : 0
    }

    static func hint(fromJSON material: [String: Any]) -> Hint {
        let factorValues = (material["emissiveFactor"] as? [Any]) ?? []
        let factor = SIMD3<Float>(
            floatValue(factorValues, 0),
            floatValue(factorValues, 1),
            floatValue(factorValues, 2)
        )
        let strength = (
            (material["extensions"] as? [String: Any])?["KHR_materials_emissive_strength"] as? [String: Any]
        ).flatMap { GLBBox.doubleValue($0["emissiveStrength"]) }.map(Float.init) ?? 1
        let albedoIndex = textureIndex(
            (material["pbrMetallicRoughness"] as? [String: Any])?["baseColorTexture"]
        ) ?? textureIndex(
            ((material["extensions"] as? [String: Any])?["KHR_materials_pbrSpecularGlossiness"] as? [String: Any])?["diffuseTexture"]
        )
        let emissiveIndex = textureIndex(material["emissiveTexture"])
        return Hint(
            factor: factor,
            strength: strength,
            hasTexture: material["emissiveTexture"] != nil,
            sharesAlbedoTexture: albedoIndex != nil && albedoIndex == emissiveIndex
        )
    }

    private static func textureIndex(_ value: Any?) -> Int? {
        GLBBox.intValue((value as? [String: Any])?["index"])
    }

    private static func floatValue(_ values: [Any], _ index: Int) -> Float {
        guard values.indices.contains(index) else { return 0 }
        return Float(GLBBox.doubleValue(values[index]) ?? 0)
    }
}
