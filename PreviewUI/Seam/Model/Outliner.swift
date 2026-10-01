import Foundation

/// One node of the typed node tree. Children are nested — the outliner renders the tree.
public struct SceneNode: Sendable, Hashable, Identifiable {
    public var id: NodeID
    public var name: String
    public var children: [SceneNode]

    public var kind: NodeKind { id.kind }

    public init(id: NodeID, name: String, children: [SceneNode] = []) {
        self.id = id
        self.name = name
        self.children = children
    }

    public init(kind: NodeKind, index: Int, name: String, children: [SceneNode] = []) {
        self.init(id: NodeID(kind: kind, index: index), name: name, children: children)
    }
}

public struct SceneInfo: Sendable, Hashable, Identifiable {
    public var id: NodeID
    public var name: String

    public init(index: Int, name: String) {
        self.id = NodeID(kind: .scene, index: index)
        self.name = name
    }
}
