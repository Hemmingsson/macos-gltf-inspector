import AppKit
import GLTFCore
import SwiftUI

/// Native sidebar outliner: `List(selection:)` + `.listStyle(.sidebar)`, one `Section` per
/// SCENE / MATERIALS / …. The scene graph is flattened to its visible rows with an indent, so each
/// row's glyph slot carries its own fold chevron (on hover) instead of a system disclosure column.
///
/// S1f: native list selection — `NodeRow` draws no selection of its own.
struct OutlinerList: View {
    var document: GLTFDocument
    var validation: ValidationResult
    @Binding var selection: NodeID?
    /// Scene / camera side effects. Selection itself is written by the list binding.
    var onActivate: (OutlinerItem) -> Void

    /// Expanded scene-graph rows. Seeded in `onAppear`, never in `init` (AGENTS.md pitfall 1).
    @State private var expanded = Set<NodeID>()

    var body: some View {
        let sections = OutlinerSection.sections(of: document)
        let foldingRoots = sections.filter(\.folds).flatMap(\.items)
        List(selection: listSelection(in: sections)) {
            ForEach(sections) { section in
                Section {
                    if section.folds {
                        ForEach(OutlinerTree.visibleRows(section.items, expanded: expanded)) { row in
                            NodeRow(
                                item: row.item,
                                isSelected: selection == row.id,
                                depth: row.depth,
                                isExpanded: row.item.hasChildren
                                    ? expanded.contains(row.id)
                                    : nil,
                                badge: badge(for: row.id),
                                onToggle: { toggle(row.item) }
                            )
                            .tag(Optional(row.id))
                        }
                    } else {
                        ForEach(section.items) { item in
                            NodeRow(item: item, isSelected: selection == item.id, badge: badge(for: item.id))
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
        .onExitCommand { selection = nil }
        .onKeyPress(.rightArrow) { fold(open: true, in: foldingRoots) }
        .onKeyPress(.leftArrow) { fold(open: false, in: foldingRoots) }
        .onKeyPress(.escape) {
            guard selection != nil else { return .ignored }
            selection = nil
            return .handled
        }
        .onAppear {
            if expanded.isEmpty { expanded = OutlinerTree.defaultExpandedIDs(roots: foldingRoots) }
        }
        .onChange(of: OutlinerTree.treeIdentity(foldingRoots)) { _, _ in
            expanded = OutlinerTree.defaultExpandedIDs(roots: foldingRoots)
        }
    }

    private func listSelection(in sections: [OutlinerSection]) -> Binding<NodeID?> {
        Binding(
            get: { selection },
            set: { newID in
                selection = newID
                if let newID, let item = Self.item(id: newID, in: sections) {
                    onActivate(item)
                }
            }
        )
    }

    /// A fault badge for rows the validator reported on. Infos and hints stay off the outliner.
    private func badge(for id: NodeID) -> DSStatus? {
        switch validation.worstSeverity(for: id) {
        case .error: .error
        case .warning: .warning
        case .info, .hint, nil: nil
        }
    }

    /// Plain click folds one row; Option-click folds or unfolds the whole subtree.
    private func toggle(_ item: OutlinerItem) {
        var next = expanded
        OutlinerTree.toggle(item, recursive: OutlinerOptionKey.isDown, expanded: &next)
        expanded = next
    }

    /// ← / → on the selected scene row folds or unfolds it, as a disclosure list does.
    private func fold(open: Bool, in roots: [OutlinerItem]) -> KeyPress.Result {
        guard let id = selection,
              let item = Self.item(id: id, in: [OutlinerSection(title: "", items: roots)]),
              item.hasChildren,
              expanded.contains(id) != open
        else { return .ignored }
        toggle(item)
        return .handled
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
