import Foundation

/// Geometry totals over a set of scene nodes: a whole scene or one node's subtree.
/// Counts follow the per-node Geometry facts: authored triangles and vertices per mesh node, not
/// multiplied by `EXT_mesh_gpu_instancing` (the instance count stays its own fact).
public struct GLTFGeometryTotals: Sendable, Equatable {
    public var nodeCount = 0
    /// Nodes that reference a mesh.
    public var meshNodeCount = 0
    /// Distinct `meshes[]` entries those nodes reference.
    public var uniqueMeshCount = 0
    public var triangleCount = 0
    public var vertexCount = 0
    /// One draw per mesh-node primitive.
    public var drawCallCount = 0
    /// Distinct materials bound by those primitives.
    public var materialCount = 0

    public init() {}
}

extension GLTFDocument {
    /// Totals of `root` and every node below it. Cycle-safe for malformed files.
    public func totals(ofSubtree root: Int) -> GLTFGeometryTotals {
        totals(roots: [root])
    }

    /// Totals of every node reachable from the scene's roots.
    public func totals(ofScene sceneIndex: Int) -> GLTFGeometryTotals {
        guard scenes.indices.contains(sceneIndex) else { return totals(roots: []) }
        return totals(roots: scenes[sceneIndex].rootNodeIndices)
    }

    /// Distinct `textures[]` entries bound by any material in the file.
    public var boundTextureCount: Int {
        Set(materials.flatMap { $0.textures.compactMap(\.textureIndex) }).count
    }

    /// Parent of each node (`nil` for roots and unreferenced nodes); the first parent wins.
    public var nodeParents: [Int?] {
        var parents = [Int?](repeating: nil, count: nodes.count)
        for node in nodes {
            for child in node.children where parents.indices.contains(child) && parents[child] == nil {
                parents[child] = node.index
            }
        }
        return parents
    }

    private func totals(roots: [Int]) -> GLTFGeometryTotals {
        var totals = GLTFGeometryTotals()
        var visited = Set<Int>()
        var meshes = Set<Int>()
        var materials = Set<Int>()
        var stack = roots.reversed().filter { nodes.indices.contains($0) }
        while let index = stack.popLast() {
            guard visited.insert(index).inserted else { continue }
            let node = nodes[index]
            totals.nodeCount += 1
            if let mesh = node.meshIndex {
                totals.meshNodeCount += 1
                meshes.insert(mesh)
                totals.triangleCount += node.triangleCount
                totals.vertexCount += node.vertexCount
                totals.drawCallCount += node.meshPrimitives.count
                materials.formUnion(node.meshPrimitives.compactMap(\.materialIndex))
            }
            stack.append(contentsOf: node.children.reversed().filter { nodes.indices.contains($0) })
        }
        totals.uniqueMeshCount = meshes.count
        totals.materialCount = materials.count
        return totals
    }
}
