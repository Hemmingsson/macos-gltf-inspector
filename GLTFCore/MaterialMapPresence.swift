import Foundation

/// Canonical texture-map presence for one material.
/// Sidebar map chips and `PreviewDebugMode` material scans share this shape.
public struct MaterialMapPresence: Sendable, Equatable {
    public var baseColor = false
    public var normal = false
    public var metallicRoughness = false
    public var occlusion = false
    public var emissive = false
    public var specular = false
    public var clearcoat = false
    public var clearcoatRoughness = false
    public var clearcoatNormal = false

    public init(
        baseColor: Bool = false,
        normal: Bool = false,
        metallicRoughness: Bool = false,
        occlusion: Bool = false,
        emissive: Bool = false,
        specular: Bool = false,
        clearcoat: Bool = false,
        clearcoatRoughness: Bool = false,
        clearcoatNormal: Bool = false
    ) {
        self.baseColor = baseColor
        self.normal = normal
        self.metallicRoughness = metallicRoughness
        self.occlusion = occlusion
        self.emissive = emissive
        self.specular = specular
        self.clearcoat = clearcoat
        self.clearcoatRoughness = clearcoatRoughness
        self.clearcoatNormal = clearcoatNormal
    }

    /// JSON material → map presence for `PreviewDebugMode` (load path has the header before convert).
    public static func from(json material: [String: Any]) -> MaterialMapPresence {
        var maps = MaterialMapPresence()
        let extensions = material["extensions"] as? [String: Any] ?? [:]
        let pbr = material["pbrMetallicRoughness"] as? [String: Any] ?? [:]
        let specGloss = extensions["KHR_materials_pbrSpecularGlossiness"] as? [String: Any]
        if pbr["baseColorTexture"] != nil || specGloss?["diffuseTexture"] != nil {
            maps.baseColor = true
        }
        if material["normalTexture"] != nil {
            maps.normal = true
        }
        if pbr["metallicRoughnessTexture"] != nil {
            maps.metallicRoughness = true
        }
        if material["occlusionTexture"] != nil {
            maps.occlusion = true
        }
        if material["emissiveTexture"] != nil {
            maps.emissive = true
        }
        if let specular = extensions["KHR_materials_specular"] as? [String: Any],
           specular["specularTexture"] != nil || specular["specularColorTexture"] != nil {
            maps.specular = true
        }
        if specGloss?["specularGlossinessTexture"] != nil {
            maps.specular = true
        }
        if let clearcoat = extensions["KHR_materials_clearcoat"] as? [String: Any] {
            if clearcoat["clearcoatTexture"] != nil { maps.clearcoat = true }
            if clearcoat["clearcoatRoughnessTexture"] != nil { maps.clearcoatRoughness = true }
            if clearcoat["clearcoatNormalTexture"] != nil { maps.clearcoatNormal = true }
        }
        return maps
    }
}

