import Foundation
import SwiftUI

// MARK: - Section model

/// One outliner row, flattened out of whatever the model calls its own hierarchy.
///
/// The views never touch `SceneModel` directly: they render `OutlinerSection`s. That keeps the
/// "which glTF array does this row come from" question in one function, and means Slice 3's
/// inspector and any later engine adapter bind to the same small value type.
///
/// Meshes may carry nested `children` for fold/unfold; flat sections leave `children` empty.
struct OutlinerItem: Identifiable, Hashable, Sendable {
    /// Also the selection key — `NodeID` already namespaces by kind, so mesh 0 and material 0
    /// cannot collide.
    var id: NodeID
    var name: String
    /// Nesting depth inside the mesh-visible tree. 0 sits flush; deeper levels step the gutter.
    var depth: Int
    /// Mesh-visible descendants only. Empty for Cameras / Lights / Materials / … .
    var children: [OutlinerItem]

    var hasChildren: Bool { !children.isEmpty }

    init(id: NodeID, name: String, depth: Int = 0, children: [OutlinerItem] = []) {
        self.id = id
        self.name = name
        self.depth = depth
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
    /// When true, rows use disclosure chevrons + guides and filter by expand state.
    /// Only Meshes sets this — other sections stay flat leaf lists.
    var folds: Bool

    init(title: String, items: [OutlinerItem], folds: Bool = false) {
        self.title = title
        self.items = items
        self.folds = folds
    }
}

extension OutlinerSection {

    /// The whole sidebar, in wireframe order: Scene · Cameras · Lights · Meshes · Materials ·
    /// Animations · Morphs.
    ///
    /// DESIGN.md's "show only what the model has" is enforced *here*, once, by simply not
    /// producing an empty section — rather than by an `if` in every view, which is how a
    /// blank-but-present header eventually sneaks in.
    static func sections(of model: some SceneModel) -> [OutlinerSection] {
        let candidates = [
            OutlinerSection(
                title: "Scene",
                items: model.scenes.map { OutlinerItem(id: $0.id, name: $0.name) }
            ),
            OutlinerSection(
                title: "Cameras",
                items: model.cameras.map { OutlinerItem(id: $0.id, name: $0.name) }
            ),
            OutlinerSection(
                title: "Lights",
                items: model.lights.map { OutlinerItem(id: $0.id, name: $0.name) }
            ),
            OutlinerSection(
                title: "Meshes",
                items: OutlinerTree.meshRoots(model.nodeTree),
                folds: true
            ),
            OutlinerSection(
                title: "Materials",
                items: model.materials.map { OutlinerItem(id: $0.id, name: $0.name) }
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

// MARK: - View

/// A quiet uppercase header with its rows under it (Main-html `.sec` + `.row`).
///
/// Takes an already-non-empty section: the decision about whether a section exists belongs to
/// `OutlinerSection.sections(of:)`, not to the thing drawing it.
struct OutlinerSectionView<Selection: SelectionModel>: View {
    var section: OutlinerSection
    var selection: Selection
    var onSelect: ((OutlinerItem) -> Void)? = nil
    /// Optional external expand set (shell proofs). Production sidebar leaves this `nil` and owns
    /// expansion in `@State` — never written from `View.init`.
    var expanded: Binding<Set<NodeID>>? = nil

    @State private var ownedExpanded = Set<NodeID>()

    private var expandedBinding: Binding<Set<NodeID>> {
        expanded ?? $ownedExpanded
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InspectorSectionHeader(title: section.title)

            if section.folds {
                ForEach(section.items) { item in
                    OutlinerTreeBranch(
                        item: item,
                        expanded: expandedBinding,
                        selection: selection
                    )
                }
            } else {
                ForEach(section.items) { item in
                    NodeRow(
                        item: item,
                        isSelected: selection.selected == item.id,
                        selection: selection
                    ) {
                        if let onSelect {
                            onSelect(item)
                        } else {
                            selection.select(selection.selected == item.id ? nil : item.id)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            guard section.folds, expanded == nil else { return }
            seedExpansionIfNeeded()
        }
        .onChange(of: OutlinerTree.treeIdentity(section.items)) { _, _ in
            guard section.folds else { return }
            expandedBinding.wrappedValue = OutlinerTree.defaultExpandedIDs(roots: section.items)
        }
    }

    /// Seed once from `onAppear` — never from `View.init` (AGENTS.md pitfall #1).
    private func seedExpansionIfNeeded() {
        guard ownedExpanded.isEmpty else { return }
        ownedExpanded = OutlinerTree.defaultExpandedIDs(roots: section.items)
    }
}

/// Recursive emit into the scroll `VStack` — only rows whose ancestors are expanded appear.
private struct OutlinerTreeBranch<Selection: SelectionModel>: View {
    let item: OutlinerItem
    @Binding var expanded: Set<NodeID>
    var selection: Selection

    private var isExpanded: Bool { expanded.contains(item.id) }

    var body: some View {
        NodeRow(
            item: item,
            isSelected: selection.selected == item.id,
            selection: selection,
            treeFolding: true,
            isExpanded: isExpanded,
            onToggleExpand: toggleExpand
        ) {
            selection.select(selection.selected == item.id ? nil : item.id)
        }

        if item.hasChildren, isExpanded {
            ForEach(item.children) { child in
                OutlinerTreeBranch(item: child, expanded: $expanded, selection: selection)
            }
        }
    }

    private func toggleExpand(recursive: Bool) {
        OutlinerTree.toggle(item, recursive: recursive, expanded: &expanded)
    }
}
