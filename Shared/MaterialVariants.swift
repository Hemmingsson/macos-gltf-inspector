import Foundation
import GLTFKit2

/// Spike helpers for `KHR_materials_variants` via GLTFKit2’s asset API.
/// SceneKit applies variants at SCN convert; RealityKit convert does not — we stamp
/// `primitive.material` from `effectiveMaterial(for:)` before our convert.
enum MaterialVariants {
    /// Named variants from `GLTFAsset.materialVariants` (empty when the extension is absent).
    static func names(from asset: GLTFAsset) -> [String] {
        guard let variants = asset.materialVariants, !variants.isEmpty else { return [] }
        return variants.enumerated().map { index, variant in
            let name = variant.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return name.isEmpty ? "Variant \(index)" : name
        }
    }

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
