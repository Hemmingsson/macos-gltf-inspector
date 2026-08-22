import RealityKit
import simd

/// Runtime morph-target weights via `BlendShapeWeightsComponent`.
enum PreviewMorph {
    /// One adjustable target on a morph mesh entity.
    struct Target: Equatable, Identifiable, Sendable {
        var id: String { "\(nodeIndex)-\(targetIndex)" }
        var nodeIndex: Int
        var targetIndex: Int
        var name: String
        var weight: Float
    }

    /// Enumerate morph entities under `root` with current weights (0…1).
    @MainActor
    static func targets(in root: Entity) -> [Target] {
        var out: [Target] = []
        func walk(_ entity: Entity) {
            if let weights = entity.components[BlendShapeWeightsComponent.self],
               !weights.weightSet.isEmpty
            {
                let nodeIndex = entity.components[GLTFNodeIDComponent.self]?.nodeIndex ?? -1
                let data = weights.weightSet[0]
                let values = Array(data.weights)
                let names = data.weightNames
                for index in values.indices {
                    out.append(
                        Target(
                            nodeIndex: nodeIndex,
                            targetIndex: index,
                            name: morphName(at: index, names: names),
                            weight: values[index]
                        )
                    )
                }
            }
            for child in entity.children {
                walk(child)
            }
        }
        walk(root)
        return out
    }

    /// Write a single target weight on the entity that owns `nodeIndex`.
    @MainActor
    static func setWeight(
        nodeIndex: Int,
        targetIndex: Int,
        value: Float,
        in root: Entity
    ) {
        guard let entity = GLTFNodeLookup.entity(nodeIndex: nodeIndex, in: root)
            ?? firstMorphEntity(in: root)
        else { return }
        setWeight(targetIndex: targetIndex, value: value, on: entity)
    }

    @MainActor
    static func setWeight(targetIndex: Int, value: Float, on entity: Entity) {
        guard var component = entity.components[BlendShapeWeightsComponent.self],
              !component.weightSet.isEmpty
        else { return }
        var data = component.weightSet[0]
        var values = Array(data.weights)
        guard values.indices.contains(targetIndex) else { return }
        values[targetIndex] = min(max(value, 0), 1)
        data.weights = BlendShapeWeights(values)
        component.weightSet[0] = data
        entity.components.set(component)
    }

    private static func morphName(at index: Int, names: [String]) -> String {
        if index < names.count, !names[index].isEmpty {
            return names[index]
        }
        return "Morph\(index)"
    }

    @MainActor
    private static func firstMorphEntity(in root: Entity) -> Entity? {
        if root.components[BlendShapeWeightsComponent.self] != nil {
            return root
        }
        for child in root.children {
            if let found = firstMorphEntity(in: child) {
                return found
            }
        }
        return nil
    }
}
