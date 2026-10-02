import RealityKit
import simd

/// Runtime morph-target weights via `BlendShapeWeightsComponent`.
@MainActor
public enum PreviewMorph {
    /// One adjustable target on a morph mesh entity.
    nonisolated public struct Target: Equatable, Identifiable, Sendable {
        public var id: String { "\(nodeIndex)-\(targetIndex)" }
        public var nodeIndex: Int
        public var targetIndex: Int
        public var name: String
        public var weight: Float
    }

    /// Enumerate morph entities under `root` with current weights (0…1).
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

    nonisolated private static func morphName(at index: Int, names: [String]) -> String {
        if index < names.count, !names[index].isEmpty {
            return names[index]
        }
        return "Morph\(index)"
    }

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
