import Foundation
import GLTFCore
import GLTFKit2

extension MaterialMapPresence {
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
}
