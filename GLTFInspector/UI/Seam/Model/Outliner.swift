import Foundation

/// One node of the typed node tree. Children are nested — the outliner renders the tree.
struct SceneNode: Sendable, Hashable, Identifiable {
    var id: NodeID
    var name: String
    var children: [SceneNode]

    init(id: NodeID, name: String, children: [SceneNode] = []) {
        self.id = id
        self.name = name
        self.children = children
    }

    init(kind: NodeKind, index: Int, name: String, children: [SceneNode] = []) {
        self.init(id: NodeID(kind: kind, index: index), name: name, children: children)
    }
}

struct SceneInfo: Sendable, Hashable, Identifiable {
    var id: NodeID
    var name: String

    init(index: Int, name: String) {
        self.id = NodeID(kind: .scene, index: index)
        self.name = name
    }
}
