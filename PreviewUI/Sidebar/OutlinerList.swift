import AppKit
import DesignSystem
import SwiftUI

/// Native sidebar outliner: `List(selection:)` + `.listStyle(.sidebar)`, one `Section` per
/// SCENE / MATERIALS / …. The scene graph is flattened to its visible rows with an indent, so each
/// row's glyph slot carries its own fold chevron (on hover) instead of a system disclosure column.
///
/// S1f: native list selection — `NodeRow` draws no selection of its own.
struct OutlinerList<Model: SceneModel, Selection: SelectionModel>: View {
    var model: Model
    var selection: Selection
    /// Scene / camera side-effects. Selection itself is written by the list binding.
    var onActivate: ((OutlinerItem) -> Void)? = nil
    /// Optional external expand set for previews/tests. The app sidebar leaves this `nil` and
    /// owns expansion in `@State` — never written from `View.init`.
    var expanded: Binding<Set<NodeID>>? = nil

    @State private var ownedExpanded = Set<NodeID>()

    init(
        model: Model,
        selection: Selection,
        onActivate: ((OutlinerItem) -> Void)? = nil,
        expanded: Binding<Set<NodeID>>? = nil
    ) {
        self.model = model
        self.selection = selection
        self.onActivate = onActivate
        self.expanded = expanded
    }

    private var expandedBinding: Binding<Set<NodeID>> {
        expanded ?? $ownedExpanded
    }

    var body: some View {
        let sections = OutlinerSection.sections(of: model)
        let foldingRoots = sections.filter(\.folds).flatMap(\.items)
        List(selection: listSelection(in: sections)) {
            ForEach(sections) { section in
                Section {
                    if section.folds {
                        ForEach(OutlinerTree.visibleRows(section.items, expanded: expandedBinding.wrappedValue)) { row in
                            NodeRow(
                                item: row.item,
                                isSelected: selection.selected == row.id,
                                depth: row.depth,
                                isExpanded: row.item.hasChildren
                                    ? expandedBinding.wrappedValue.contains(row.id)
                                    : nil,
                                onToggle: { toggle(row.item) }
                            )
                            .tag(Optional(row.id))
                        }
                    } else {
                        ForEach(section.items) { item in
                            NodeRow(item: item, isSelected: selection.selected == item.id)
                                .tag(Optional(item.id))
                        }
                    }
                } header: {
                    DSSectionHeader(section.title)
                }
            }
        }
        .listStyle(.sidebar)
        // Compact rows (11 pt), like a design tool's layer list, whatever the system sidebar size.
        .environment(\.sidebarRowSize, .small)
        .focusSection()
        .onExitCommand { selection.select(nil) }
        .onKeyPress(.rightArrow) { fold(open: true, in: foldingRoots) }
        .onKeyPress(.leftArrow) { fold(open: false, in: foldingRoots) }
        .onKeyPress(.escape) {
            guard selection.selected != nil else { return .ignored }
            selection.select(nil)
            return .handled
        }
        .onAppear {
            guard expanded == nil else { return }
            seedExpansionIfNeeded(roots: foldingRoots)
        }
        .onChange(of: OutlinerTree.treeIdentity(foldingRoots)) { _, _ in
            expandedBinding.wrappedValue = OutlinerTree.defaultExpandedIDs(roots: foldingRoots)
        }
    }

    private func listSelection(in sections: [OutlinerSection]) -> Binding<NodeID?> {
        Binding(
            get: { selection.selected },
            set: { newID in
                selection.select(newID)
                if let newID, let item = Self.item(id: newID, in: sections) {
                    onActivate?(item)
                }
            }
        )
    }

    /// Plain click folds one row; Option-click folds or unfolds the whole subtree.
    private func toggle(_ item: OutlinerItem) {
        var next = expandedBinding.wrappedValue
        OutlinerTree.toggle(item, recursive: OutlinerOptionKey.isDown, expanded: &next)
        expandedBinding.wrappedValue = next
    }

    /// ← / → on the selected scene row folds or unfolds it, as a disclosure list does.
    private func fold(open: Bool, in roots: [OutlinerItem]) -> KeyPress.Result {
        guard let id = selection.selected,
              let item = Self.item(id: id, in: [OutlinerSection(title: "", items: roots)]),
              item.hasChildren,
              expandedBinding.wrappedValue.contains(id) != open
        else { return .ignored }
        toggle(item)
        return .handled
    }

    /// Seed once from `onAppear` — never from `View.init` (AGENTS.md pitfall #1).
    private func seedExpansionIfNeeded(roots: [OutlinerItem]) {
        guard ownedExpanded.isEmpty else { return }
        ownedExpanded = OutlinerTree.defaultExpandedIDs(roots: roots)
    }

    private static func item(id: NodeID, in sections: [OutlinerSection]) -> OutlinerItem? {
        func walk(_ items: [OutlinerItem]) -> OutlinerItem? {
            for item in items {
                if item.id == id { return item }
                if let found = walk(item.children) { return found }
            }
            return nil
        }
        for section in sections {
            if let found = walk(section.items) { return found }
        }
        return nil
    }
}

/// Option-key read for folding: Option-click expands or collapses the whole subtree.
enum OutlinerOptionKey {
    static var isDown: Bool {
        let eventFlags = NSApp.currentEvent?.modifierFlags ?? []
        return eventFlags.contains(.option) || NSEvent.modifierFlags.contains(.option)
    }
}

// MARK: - Previews

private struct OutlinerListPreviewHost: View {
    @State private var selection: MockSelectionModel
    @State private var expanded: Set<NodeID>

    init() {
        _selection = State(initialValue: MockSelectionModel(selected: nil))
        _expanded = State(initialValue: OutlinerTree.defaultExpandedIDs(roots: OutlinerFixtures.cubeScene))
    }

    var body: some View {
        PreviewCanvas(width: DS.Metrics.sidebarWidth, height: 280) {
            OutlinerList(
                model: FixtureSceneModel.cube,
                selection: selection,
                expanded: $expanded
            )
        }
    }
}

#Preview("cube", traits: .fixedLayout(width: 248, height: 280)) {
    OutlinerListPreviewHost()
}
