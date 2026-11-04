import Foundation

/// glTF animation channel target path, shaped for future `KHR_animation_pointer`.
public enum AnimationChannelPath: String, Sendable, Hashable {
    case translation
    case rotation
    case scale
    case weights
}

/// Identifies one animatable property for disjoint-clip selection and pose application.
public struct AnimationTargetKey: Sendable, Hashable {
    public var path: AnimationChannelPath
    /// Set for TRS and for weights animated on the node’s own weight array.
    public var nodeIndex: Int?
    /// Set when the channel drives `/meshes/m/weights` (node has no weights).
    public var meshIndex: Int?

    public init(path: AnimationChannelPath, nodeIndex: Int? = nil, meshIndex: Int? = nil) {
        self.path = path
        self.nodeIndex = nodeIndex
        self.meshIndex = meshIndex
    }
}

/// Resolved channel target after parsing glTF (pointer case reserved).
public enum AnimationChannelTarget: Sendable, Equatable {
    case translation(nodeIndex: Int)
    case rotation(nodeIndex: Int)
    case scale(nodeIndex: Int)
    case weightsOnNode(nodeIndex: Int)
    case weightsOnMesh(meshIndex: Int)
    case pointer(String)

    public var key: AnimationTargetKey {
        switch self {
        case let .translation(nodeIndex):
            AnimationTargetKey(path: .translation, nodeIndex: nodeIndex)
        case let .rotation(nodeIndex):
            AnimationTargetKey(path: .rotation, nodeIndex: nodeIndex)
        case let .scale(nodeIndex):
            AnimationTargetKey(path: .scale, nodeIndex: nodeIndex)
        case let .weightsOnNode(nodeIndex):
            AnimationTargetKey(path: .weights, nodeIndex: nodeIndex)
        case let .weightsOnMesh(meshIndex):
            AnimationTargetKey(path: .weights, meshIndex: meshIndex)
        case .pointer:
            AnimationTargetKey(path: .translation, nodeIndex: -1)
        }
    }

    public var nodeIndexForMatrixSkip: Int? {
        switch self {
        case let .translation(i), let .rotation(i), let .scale(i), let .weightsOnNode(i):
            i
        case .weightsOnMesh, .pointer:
            nil
        }
    }
}
