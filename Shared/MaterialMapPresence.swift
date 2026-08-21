import Foundation
import GLTFKit2

/// Canonical texture-map presence for one material.
/// Sidebar map chips and `PreviewDebugMode` material scans share this shape.
struct MaterialMapPresence: Sendable, Equatable {
    var baseColor = false
    var normal = false
    var metallicRoughness = false
    var occlusion = false
    var emissive = false
    var specular = false
    var clearcoat = false
    var clearcoatRoughness = false
    var clearcoatNormal = false

    static func from(gltf material: GLTFMaterial) -> MaterialMapPresence {
        var maps = MaterialMapPresence()
        if material.metallicRoughness?.baseColorTexture != nil
            || material.specularGlossiness?.diffuseTexture != nil {
            maps.baseColor = true
        }
        if material.normalTexture != nil {
            maps.normal = true
        }
        if material.metallicRoughness?.metallicRoughnessTexture != nil {
            maps.metallicRoughness = true
        }
        if material.occlusionTexture != nil {
            maps.occlusion = true
        }
        if material.emissive?.emissiveTexture != nil {
            maps.emissive = true
        }
        if material.specular?.specularTexture != nil
            || material.specular?.specularColorTexture != nil
            || material.specularGlossiness?.specularGlossinessTexture != nil {
            maps.specular = true
        }
        if let clearcoat = material.clearcoat {
            if clearcoat.clearcoatTexture != nil { maps.clearcoat = true }
            if clearcoat.clearcoatRoughnessTexture != nil { maps.clearcoatRoughness = true }
            if clearcoat.clearcoatNormalTexture != nil { maps.clearcoatNormal = true }
        }
        return maps
    }

    /// JSON twin of `from(gltf:)` for `PreviewDebugMode` (load path has the header before convert).
    static func from(json material: [String: Any]) -> MaterialMapPresence {
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
