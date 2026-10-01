import Foundation

/// Which view modes a file has data for, from the glTF JSON alone. Both renderers start from
/// this list, so the view-mode menu shows what the file has and not what one converter kept.
public struct ViewModeAvailability: Sendable, Equatable {
    /// Channels with data, in menu order.
    public var channels: [RenderViewMode.Channel] {
        let gated: [(Bool, RenderViewMode.Channel)] = [
            (hasNormals, .normals),
            (hasUVs, .textureCoordinates),
            (hasBase, .baseColor),
            (hasMetallic, .metallic),
            (hasRoughness, .roughness),
            (hasAO, .ambientOcclusion),
            (hasEmissive, .emissive),
            (hasAlpha, .alpha),
            (hasSpecular, .specular),
            (hasTangents, .tangents),
            (hasClearcoat, .clearcoat),
            (hasClearcoatRoughness, .clearcoatRoughness),
            (hasClearcoatNormal, .clearcoatNormal),
        ]
        return gated.filter(\.0).map(\.1)
    }

    /// Shaded, wireframe when there are triangles, then `channels`.
    public var viewModes: [RenderViewMode] {
        [.shaded] + (hasTriangles ? [.wireframe] : []) + channels.map(RenderViewMode.channel)
    }

    public private(set) var hasTriangles = false
    public private(set) var hasVertexColors = false
    private var hasNormals = false
    private var hasUVs = false
    private var hasTangents = false
    private var hasBase = false
    private var hasMetallic = false
    private var hasRoughness = false
    private var hasAO = false
    private var hasEmissive = false
    private var hasAlpha = false
    private var hasSpecular = false
    private var hasClearcoat = false
    private var hasClearcoatRoughness = false
    private var hasClearcoatNormal = false

    public init(json: [String: Any]) {
        scanMeshes(json["meshes"] as? [[String: Any]] ?? [])
        scanMaterials(json["materials"] as? [[String: Any]] ?? [])
    }

    private mutating func scanMeshes(_ meshes: [[String: Any]]) {
        for mesh in meshes {
            for primitive in mesh["primitives"] as? [[String: Any]] ?? [] {
                let attributes = primitive["attributes"] as? [String: Any] ?? [:]
                if attributes["NORMAL"] != nil { hasNormals = true }
                if attributes["TANGENT"] != nil { hasTangents = true }
                if attributes.keys.contains(where: { $0.hasPrefix("TEXCOORD_") }) {
                    hasUVs = true
                }
                if attributes.keys.contains(where: { $0.hasPrefix("COLOR_") }) {
                    hasVertexColors = true
                }
                let mode = GLTFJSON.int(primitive["mode"]) ?? 4
                if mode == 4 || mode == 5 || mode == 6 {
                    hasTriangles = true
                }
            }
        }
    }

    private mutating func scanMaterials(_ materials: [[String: Any]]) {
        if !materials.isEmpty {
            hasBase = true
        }
        for material in materials {
            let extensions = material["extensions"] as? [String: Any] ?? [:]
            let unlit = extensions["KHR_materials_unlit"] != nil
            let specGloss = extensions["KHR_materials_pbrSpecularGlossiness"] != nil
            let maps = MaterialMapPresence.from(json: material)

            if maps.specular || extensions["KHR_materials_specular"] != nil || specGloss {
                hasSpecular = true
            }
            if let alpha = material["alphaMode"] as? String,
               alpha == "MASK" || alpha == "BLEND" {
                hasAlpha = true
            }
            if maps.normal {
                hasNormals = true
            }
            if maps.occlusion {
                hasAO = true
            }
            if maps.emissive {
                hasEmissive = true
            }
            if let emissive = GLTFJSON.float3(material["emissiveFactor"]), !nearZero(emissive) {
                hasEmissive = true
            }

            let metalRough = !unlit && !specGloss
            if metalRough {
                let pbr = material["pbrMetallicRoughness"] as? [String: Any] ?? [:]
                if maps.metallicRoughness || hasNonDefault(pbr["metallicFactor"], default: 1) {
                    hasMetallic = true
                }
                if maps.metallicRoughness || hasNonDefault(pbr["roughnessFactor"], default: 1) {
                    hasRoughness = true
                }
            }

            if maps.clearcoat {
                hasClearcoat = true
            }
            if maps.clearcoatRoughness {
                hasClearcoatRoughness = true
            }
            if maps.clearcoatNormal {
                hasClearcoatNormal = true
            }
            if let clearcoat = extensions["KHR_materials_clearcoat"] as? [String: Any] {
                if hasNonDefault(clearcoat["clearcoatFactor"], default: 0) {
                    hasClearcoat = true
                }
                if hasNonDefault(clearcoat["clearcoatRoughnessFactor"], default: 0) {
                    hasClearcoatRoughness = true
                }
            }
        }
    }

    private func hasNonDefault(_ value: Any?, default expected: Double) -> Bool {
        guard let number = GLTFJSON.double(value) else { return false }
        return abs(number - expected) > 0.0001
    }

    private func nearZero(_ value: SIMD3<Float>) -> Bool {
        abs(value.x) < 0.0001 && abs(value.y) < 0.0001 && abs(value.z) < 0.0001
    }
}

