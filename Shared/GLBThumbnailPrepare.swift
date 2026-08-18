import RealityKit

/// Softens PBR for Finder icons: less specular blowout, more readable albedo.
enum GLBThumbnailPrepare {
    @MainActor
    static func apply(to entity: Entity) {
        applyRecursive(entity)
    }

    @MainActor
    private static func applyRecursive(_ entity: Entity) {
        if var model = entity.components[ModelComponent.self] {
            model.materials = model.materials.map(flatten)
            entity.components.set(model)
        }
        for child in entity.children {
            applyRecursive(child)
        }
    }

    private static func flatten(_ material: RealityKit.Material) -> RealityKit.Material {
        guard var pbr = material as? PhysicallyBasedMaterial else { return material }
        pbr.roughness = .init(floatLiteral: 0.85)
        pbr.metallic = .init(floatLiteral: 0)
        pbr.specular = .init(floatLiteral: 0)
        pbr.clearcoat = .init(floatLiteral: 0)
        return pbr
    }
}
