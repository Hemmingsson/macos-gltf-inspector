import RealityKit

struct GLTFNodeIDComponent: Component, Codable {
    var nodeIndex: Int
}

enum GLTFNodeLookup {
    @MainActor
    static func entity(nodeIndex: Int, in root: Entity) -> Entity? {
        if root.components[GLTFNodeIDComponent.self]?.nodeIndex == nodeIndex {
            return root
        }
        for child in root.children {
            if let found = entity(nodeIndex: nodeIndex, in: child) {
                return found
            }
        }
        return nil
    }
}
