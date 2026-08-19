import RealityKit

enum GLBPreviewScenery {
    /// Point / spot / directional components only — not `DirectionalLightComponent.Shadow()`.
    @MainActor
    static func punctualLightCount(in entity: Entity) -> Int {
        var count = 0
        walk(entity) { node in
            if node.components[PointLightComponent.self] != nil { count += 1 }
            if node.components[SpotLightComponent.self] != nil { count += 1 }
            if node.components[DirectionalLightComponent.self] != nil { count += 1 }
        }
        return count
    }

    @MainActor
    private static func walk(_ entity: Entity, _ visit: (Entity) -> Void) {
        visit(entity)
        for child in entity.children {
            walk(child, visit)
        }
    }
}
