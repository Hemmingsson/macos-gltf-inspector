import Foundation
import GLTFKit2

/// `KHR_materials_variants` on GLTFKit2’s asset: RealityKit convert does not apply variants, so we
/// stamp `primitive.material` from `effectiveMaterial(for:)` before our convert. Variant names come
/// from the JSON (`GLTFDocumentJSON.materialVariantNames`).
enum MaterialVariants {
    /// Replace each primitive’s default material with the mapped variant material when present.
    static func apply(variantIndex: Int, to asset: GLTFAsset) {
        guard let variants = asset.materialVariants, variants.indices.contains(variantIndex) else {
            return
        }
        let variant = variants[variantIndex]
        for mesh in asset.meshes {
            for primitive in mesh.primitives {
                primitive.material = primitive.effectiveMaterial(for: variant)
            }
        }
    }
}
