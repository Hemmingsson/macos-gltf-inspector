import AppKit
import DesignSystem
import SwiftUI

/// Native sidebar outliner: `List(selection:)` + `.listStyle(.sidebar)`, one `Section` per
/// SCENE / MATERIALS / …, recursive `DisclosureGroup`s bound to the existing expansion set.
///
/// S1f: native list selection — `NodeRow` draws no selection of its own.
public struct OutlinerList<Model: SceneModel, Selection: SelectionModel>: View {
    public var model: Model
    public var selection: Selection
    /// Scene / camera side-effects. Selection itself is written by the list binding.
    public var onActivate: ((OutlinerItem) -> Void)? = nil
    /// Optional external expand set for previews/tests. The app sidebar leaves this `nil` and
    /// owns expansion in `@State` — never written from `View.init`.
    public var expanded: Binding<Set<NodeID>>? = nil

    @State private var ownedExpanded = Set<NodeID>()

    public init(
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

    public var body: some View {
        let sections = OutlinerSection.sections(of: model)
        let foldingRoots = sections.filter(\.folds).flatMap(\.items)
        List(selection: listSelection(in: sections)) {
            ForEach(sections) { section in
                Section {
                    if section.folds {
                        ForEach(section.items) { item in
                            OutlinerDisclosure(
                                item: item,
                                expanded: expandedBinding,
                                selection: selection
                            )
                        }
                    } else {
                        ForEach(section.items) { item in
                            NodeRow(item: item, isSelected: selection.selected == item.id, selection: selection)
                                .tag(Optional(item.id))
                        }
                    }
                } header: {
                    DSSectionHeader(section.title)
                }
            }
        }
        .listStyle(.sidebar)
        .focusSection()
        .onExitCommand { selection.select(nil) }
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

/// Recursive scene-graph branch. Expansion is the shared `Set<NodeID>`; Option-click still
/// expands or collapses the whole subtree via `OutlinerTree.toggle`.
struct OutlinerDisclosure<Selection: SelectionModel>: View {
    let item: OutlinerItem
    @Binding var expanded: Set<NodeID>
    var selection: Selection

    var body: some View {
        if item.hasChildren {
            DisclosureGroup(isExpanded: disclosureExpanded) {
                ForEach(item.children) { child in
                    OutlinerDisclosure(item: child, expanded: $expanded, selection: selection)
                }
            } label: {
                NodeRow(item: item, isSelected: selection.selected == item.id, selection: selection)
            }
            .tag(Optional(item.id))
        } else {
            NodeRow(item: item, isSelected: selection.selected == item.id, selection: selection)
                .tag(Optional(item.id))
        }
    }

    /// Forwards the system chevron into the existing expansion set. Option-click ignores the
    /// incoming bool and runs the subtree toggle (expand-if-partial, collapse-if-full).
    private var disclosureExpanded: Binding<Bool> {
        Binding(
            get: { expanded.contains(item.id) },
            set: { newValue in
                var next = expanded
                if OutlinerOptionKey.isDown {
                    OutlinerTree.toggle(item, recursive: true, expanded: &next)
                } else if newValue {
                    next.insert(item.id)
                } else {
                    next.remove(item.id)
                }
                expanded = next
            }
        )
    }
}

/// Shared Option-key read for disclosure (subtree) and the eye button (isolate).
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
