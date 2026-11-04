import Foundation
import GLTFCore

// MARK: - Section model

/// One outliner row. The views render `OutlinerSection`s, which keeps the "which glTF array does
/// this row come from" question in one function. Scene-graph rows carry their `children`.
struct OutlinerItem: Identifiable, Hashable, Sendable {
    /// Also the selection key — `NodeID` already namespaces by kind, so mesh 0 and material 0
    /// cannot collide.
    var id: NodeID
    var name: String
    /// Scene-graph descendants.
    var children: [OutlinerItem]

    var hasChildren: Bool { !children.isEmpty }

    init(id: NodeID, name: String, children: [OutlinerItem] = []) {
        self.id = id
        self.name = name
        self.children = children
    }
}

/// A titled run of rows. Constructed only when it has members — see `sections(of:)`.
struct OutlinerSection: Identifiable, Hashable, Sendable {
    /// Titles are a fixed vocabulary and unique within the sidebar, so they are a stable
    /// `ForEach` identity that survives a fixture change (unlike an index).
    var id: String { title }
    var title: String
    var items: [OutlinerItem]
    /// When true, rows nest in disclosure groups.
    /// Only the Scene graph section sets this — other sections stay flat leaf lists.
    var folds: Bool

    init(title: String, items: [OutlinerItem], folds: Bool = false) {
        self.title = title
        self.items = items
        self.folds = folds
    }
}

extension OutlinerSection {
    /// The whole sidebar, in order: Scenes · Scene · Materials · Skins · Animations · Morphs.
    ///
    /// DESIGN.md's "show only what the model has" is enforced here, once, by not producing an
    /// empty section, rather than by an `if` in every view.
    static func sections(of document: GLTFDocument) -> [OutlinerSection] {
        func items(_ kind: NodeKind, count: Int, where include: (Int) -> Bool = { _ in true }) -> [OutlinerItem] {
            (0..<count).filter(include).map { index in
                let id = NodeID(kind: kind, index: index)
                return OutlinerItem(id: id, name: document.displayName(of: id))
            }
        }
        let candidates = [
            // Plural: the scene picker, distinct from the "Scene" graph below it. Titles are the
            // section identity, so the two must never collide.
            OutlinerSection(title: "Scenes", items: document.scenes.count > 1 ? items(.scene, count: document.scenes.count) : []),
            OutlinerSection(title: "Scene", items: sceneGraph(document), folds: true),
            OutlinerSection(title: "Materials", items: items(.material, count: document.materials.count)),
            OutlinerSection(title: "Skins", items: items(.skin, count: document.skins.count)),
            OutlinerSection(title: "Animations", items: items(.animation, count: document.animations.count) {
                document.animations[$0].duration > 0
            }),
            OutlinerSection(title: "Morphs", items: items(.morph, count: document.morphs.count)),
        ]
        return candidates.filter { !$0.items.isEmpty }
    }

    /// Every scene's roots, each once, with their children; a node reached again through a
    /// cycle is shown without children. A file with no scenes lists its parentless nodes.
    private static func sceneGraph(_ document: GLTFDocument) -> [OutlinerItem] {
        func item(_ index: Int, path: Set<Int>) -> OutlinerItem? {
            guard let id = document.id(ofNode: index) else { return nil }
            let children = path.contains(index)
                ? []
                : document.nodes[index].children.compactMap { item($0, path: path.union([index])) }
            return OutlinerItem(id: id, name: document.displayName(of: id), children: children)
        }
        var roots = document.scenes.flatMap(\.rootNodeIndices)
        if roots.isEmpty {
            let children = Set(document.nodes.flatMap(\.children))
            roots = document.nodes.map(\.index).filter { !children.contains($0) }
        }
        var seen = Set<Int>()
        return roots.filter { seen.insert($0).inserted }.compactMap { item($0, path: []) }
    }
}
