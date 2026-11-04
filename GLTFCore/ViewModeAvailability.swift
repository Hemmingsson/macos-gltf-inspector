import Foundation

/// Which view modes a file has data for, from the glTF JSON alone, so the view-mode menu shows
/// only what the file has.
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

    /// Shaded, the triangle modes when there are triangles, then `channels`.
    public var viewModes: [RenderViewMode] {
        [.shaded] + (hasTriangles ? RenderViewMode.displayModes : []) + channels.map(RenderViewMode.channel)
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
        hasBase = hasBase || !materials.isEmpty
        for material in materials {
            let extensions = material["extensions"] as? [String: Any] ?? [:]
            let unlit = extensions["KHR_materials_unlit"] != nil
            let specGloss = extensions["KHR_materials_pbrSpecularGlossiness"] != nil
            let maps = Set(GLTFDocumentJSON.textureRefs(material).map(\.kind))
            let alphaMode = material["alphaMode"] as? String
            let emissiveFactor = GLTFJSON.float3(material["emissiveFactor"])
            let pbr = material["pbrMetallicRoughness"] as? [String: Any] ?? [:]
            let metalRough = !unlit && !specGloss
            let clearcoat = extensions["KHR_materials_clearcoat"] as? [String: Any] ?? [:]

            hasSpecular = hasSpecular || maps.contains(.specular) || specGloss || extensions["KHR_materials_specular"] != nil
            hasAlpha = hasAlpha || alphaMode == "MASK" || alphaMode == "BLEND"
            hasNormals = hasNormals || maps.contains(.normal)
            hasAO = hasAO || maps.contains(.occlusion)
            hasEmissive = hasEmissive || maps.contains(.emissive) || !nearZero(emissiveFactor ?? .zero)
            hasMetallic = hasMetallic
                || (metalRough && (maps.contains(.metallicRoughness) || hasNonDefault(pbr["metallicFactor"], default: 1)))
            hasRoughness = hasRoughness
                || (metalRough && (maps.contains(.metallicRoughness) || hasNonDefault(pbr["roughnessFactor"], default: 1)))
            hasClearcoat = hasClearcoat || maps.contains(.clearcoat)
                || hasNonDefault(clearcoat["clearcoatFactor"], default: 0)
            hasClearcoatRoughness = hasClearcoatRoughness || maps.contains(.clearcoatRoughness)
                || hasNonDefault(clearcoat["clearcoatRoughnessFactor"], default: 0)
            hasClearcoatNormal = hasClearcoatNormal || maps.contains(.clearcoatNormal)
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

