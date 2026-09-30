import Foundation
import GLTFKit2
import RealityKit

/// `KHR_texture_transform` and `texCoord` → RealityKit material parameters. RealityKit has one
/// transform per UV set per material (`textureCoordinateTransform` for UV0,
/// `secondaryTextureCoordinateTransform` for UV1) and a UV set per texture (`Texture.uvIndex`).
/// glTF allows a transform per texture; when textures on one set disagree, the base colour's
/// (else the first textured slot's) wins and the loss is reported.
enum TextureTransforms {
    struct Slot {
        let params: GLTFTextureParams
        let uvSet: Int
    }

    /// The UV set a texture samples: the transform's `texCoord` override, else `texCoord`.
    /// RealityKit meshes carry two sets; anything above falls back to UV0.
    static func uvSet(of params: GLTFTextureParams) -> Int {
        let raw = params.transform.flatMap { $0.hasTexCoord ? Int($0.texCoord) : nil } ?? params.texCoord
        return raw == 1 ? 1 : 0
    }

    /// Every texture convert binds, base colour first.
    static func slots(of material: GLTFMaterial) -> [Slot] {
        let params: [GLTFTextureParams?] = [
            material.metallicRoughness?.baseColorTexture,
            material.metallicRoughness?.metallicRoughnessTexture,
            material.normalTexture,
            material.occlusionTexture,
            material.emissive?.emissiveTexture,
            material.specular?.specularTexture,
            material.clearcoat?.clearcoatTexture,
            material.clearcoat?.clearcoatRoughnessTexture,
            material.clearcoat?.clearcoatNormalTexture,
            material.sheen?.sheenColorTexture,
        ]
        return params.compactMap { $0.map { Slot(params: $0, uvSet: uvSet(of: $0)) } }
    }

    /// RealityKit transform per UV set that has a textured slot.
    static func transforms(
        for material: GLTFMaterial,
        context: RealityKitResourceContext
    ) -> [Int: MaterialParameterTypes.TextureCoordinateTransform] {
        var out: [Int: MaterialParameterTypes.TextureCoordinateTransform] = [:]
        let slots = slots(of: material)
        for set in 0..<2 {
            let onSet = slots.filter { $0.uvSet == set }
            guard let chosen = onSet.first else { continue }
            if onSet.contains(where: { !same($0.params.transform, chosen.params.transform) }) {
                context.record(
                    .approximatedTextureTransform,
                    severity: .warning,
                    message: "Textures on UV\(set) use different KHR_texture_transform; one applies to all",
                    materialName: material.name
                )
            }
            out[set] = realityKit(chosen.params.transform)
        }
        return out
    }

    /// RealityKit applies the transform in image space (V down, its V flip undone), which is
    /// glTF's own UV space: offset and scale carry over unchanged and the order is glTF's
    /// `T · R · S`; only the rotation sense is opposite. Probed per parameter, then verified
    /// against pre-transformed UVs on UV0 and UV1 (`TextureTransformConvertTests`).
    static func realityKit(_ transform: GLTFTextureTransform?) -> MaterialParameterTypes.TextureCoordinateTransform {
        guard let transform else { return .init() }
        return .init(offset: transform.offset, scale: transform.scale, rotation: -transform.rotation)
    }

    private static func same(_ a: GLTFTextureTransform?, _ b: GLTFTextureTransform?) -> Bool {
        let identity = (offset: SIMD2<Float>(0, 0), rotation: Float(0), scale: SIMD2<Float>(1, 1))
        let x = a.map { ($0.offset, $0.rotation, $0.scale) } ?? identity
        let y = b.map { ($0.offset, $0.rotation, $0.scale) } ?? identity
        return x.0 == y.0 && x.1 == y.1 && x.2 == y.2
    }
}
