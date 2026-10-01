import Foundation

// MARK: - Section model

/// One outliner row, flattened out of whatever the model calls its own hierarchy.
///
/// The views never touch `SceneModel` directly: they render `OutlinerSection`s. That keeps the
/// "which glTF array does this row come from" question in one function, and lets the inspector
/// and any engine adapter bind to the same small value type.
///
/// Any scene-graph node may carry nested `children` for fold/unfold.
public struct OutlinerItem: Identifiable, Hashable, Sendable {
    /// Also the selection key — `NodeID` already namespaces by kind, so mesh 0 and material 0
    /// cannot collide.
    public var id: NodeID
    public var name: String
    /// Scene-graph descendants.
    public var children: [OutlinerItem]

    public var hasChildren: Bool { !children.isEmpty }

    public init(id: NodeID, name: String, children: [OutlinerItem] = []) {
        self.id = id
        self.name = name
        self.children = children
    }
}

/// A titled run of rows. Constructed only when it has members — see `sections(of:)`.
public struct OutlinerSection: Identifiable, Hashable, Sendable {
    /// Titles are a fixed vocabulary and unique within the sidebar, so they are a stable
    /// `ForEach` identity that survives a fixture change (unlike an index).
    public var id: String { title }
    public var title: String
    public var items: [OutlinerItem]
    /// When true, rows nest in disclosure groups.
    /// Only the Scene graph section sets this — other sections stay flat leaf lists.
    public var folds: Bool

    public init(title: String, items: [OutlinerItem], folds: Bool = false) {
        self.title = title
        self.items = items
        self.folds = folds
    }
}

public extension OutlinerSection {

    /// The whole sidebar, in wireframe order: Scenes · Scene · Materials · Skins · Animations · Morphs.
    ///
    /// DESIGN.md's "show only what the model has" is enforced *here*, once, by simply not
    /// producing an empty section — rather than by an `if` in every view, which is how a
    /// blank-but-present header eventually sneaks in.
    static func sections(of model: some SceneModel) -> [OutlinerSection] {
        let candidates = [
            // Plural: the scene *picker*, distinct from the "Scene" graph below it. Titles are
            // the section identity, so the two must never collide.
            OutlinerSection(
                title: "Scenes",
                items: model.scenes.count > 1
                    ? model.scenes.map { OutlinerItem(id: $0.id, name: $0.name) }
                    : []
            ),
            OutlinerSection(
                title: "Scene",
                items: OutlinerTree.fullRoots(model.nodeTree),
                folds: true
            ),
            OutlinerSection(
                title: "Materials",
                items: model.materials.map { OutlinerItem(id: $0.id, name: $0.name) }
            ),
            OutlinerSection(
                title: "Skins",
                items: model.skins.map { OutlinerItem(id: $0.id, name: $0.name) }
            ),
            OutlinerSection(
                title: "Animations",
                items: model.animations.map { OutlinerItem(id: $0.id, name: $0.name) }
            ),
            OutlinerSection(
                title: "Morphs",
                items: model.morphs.map {
                    OutlinerItem(id: $0.id, name: $0.meshName)
                }
            )
        ]
        return candidates.filter { !$0.items.isEmpty }
    }
}
