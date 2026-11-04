import AppKit
import GLTFCore
import SwiftUI

/// Native sidebar outliner: `List(selection:)` + `.listStyle(.sidebar)`, one `Section` per
/// SCENE / MATERIALS / …. The scene graph is flattened to its visible rows with an indent, so each
/// row's glyph slot carries its own fold chevron instead of a system disclosure column.
///
/// S1f: native list selection — `NodeRow` draws no selection of its own.
struct OutlinerList: View {
    var document: GLTFDocument
    var validation: ValidationResult
    /// The primary row (inspector, reveal, ← / →).
    @Binding var selection: NodeID?
    /// Every selected row; ⌘- and ⇧-click extend it as in any macOS list.
    @Binding var selectedIDs: Set<NodeID>
    /// Scene / camera side effects. Selection itself is written by the list binding.
    var onActivate: (OutlinerItem) -> Void
    /// This window's hidden and soloed scene nodes (glTF node indices).
    var hiddenNodes: Set<Int> = []
    var soloNodes: Set<Int> = []
    var onToggleHidden: (Int) -> Void = { _ in }
    var onToggleSolo: (Int) -> Void = { _ in }
    var onShowAll: () -> Void = {}
    /// Frame the camera on this scene node (also selects it).
    var onFrame: (Int) -> Void = { _ in }
    /// glTF node under the canvas pointer; its row gets the pre-selection tint.
    var pointedNode: Int?
    /// Nodes targeted by the active animation clips (scene graph only).
    var animatedSceneNodes: Set<Int> = []
    /// Hairline tree guides in the indent (Settings ▸ General, default on).
    var showsTreeGuides = true

    /// Expanded scene-graph rows. Seeded in `onAppear`, never in `init` (AGENTS.md pitfall 1).
    @State private var expanded = Set<NodeID>()

    var body: some View {
        let sections = OutlinerSection.sections(of: document)
        let foldingRoots = sections.filter(\.folds).flatMap(\.items)
        let layers = OutlinerTree.layerVisibility(
            foldingRoots,
            isHiddenInFile: { document.nodes.indices.contains($0) && document.nodes[$0].isHiddenInFile },
            hidden: hiddenNodes,
            solo: soloNodes
        )
        let meshRefs = document.meshReferenceCounts()
        ScrollViewReader { proxy in
            List(selection: listSelection(in: sections)) {
                ForEach(sections) { section in
                    Section {
                        if section.folds {
                            ForEach(OutlinerTree.visibleRows(section.items, expanded: expanded)) { row in
                                NodeRow(
                                    item: row.item,
                                    isJoint: isJoint(row.id),
                                    isSelected: selectedIDs.contains(row.id),
                                    depth: row.depth,
                                    isExpanded: row.item.hasChildren
                                        ? expanded.contains(row.id)
                                        : nil,
                                    badge: badge(for: row.id),
                                    systemImage: document.systemImage(for: row.id),
                                    assetImage: document.assetImage(for: row.id, meshRefs: meshRefs),
                                    swatchColor: document.swatchColor(for: row.id),
                                    kindTitle: document.displayKindTitle(of: row.id),
                                    visibility: layers[row.id],
                                    isPointed: row.id.kind.isSceneNode && row.id.index == pointedNode,
                                    showsAnimatedIndicator: row.id.kind.isSceneNode && animatedSceneNodes.contains(row.id.index),
                                    onVisibility: { solo in
                                        if solo { onToggleSolo(row.id.index) } else { onToggleHidden(row.id.index) }
                                    },
                                    onToggle: { toggle(row.item) },
                                    guides: showsTreeGuides ? row.guides : nil
                                )
                                .id(row.id)
                                .tag(row.id)
                                .contextMenu { layerMenu(for: row.id, state: layers[row.id]) }
                            }
                        } else {
                            ForEach(section.items) { item in
                                NodeRow(
                                    item: item,
                                    isJoint: isJoint(item.id),
                                    isSelected: selectedIDs.contains(item.id),
                                    badge: badge(for: item.id),
                                    systemImage: document.systemImage(for: item.id),
                                    assetImage: document.assetImage(for: item.id, meshRefs: meshRefs),
                                    swatchColor: document.swatchColor(for: item.id),
                                    kindTitle: document.displayKindTitle(of: item.id)
                                )
                                .id(item.id)
                                .tag(item.id)
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
            .onChange(of: selection) { _, newID in
                guard let newID, newID.kind.isSceneNode else { return }
                var next = expanded
                OutlinerTree.reveal(newID, in: foldingRoots, expanded: &next)
                expanded = next
                // After expansion, scroll on the next turn so the row exists in the list.
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(newID, anchor: .center)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func layerMenu(for id: NodeID, state: DSVisibility?) -> some View {
        let isHidden = hiddenNodes.contains(id.index)
        let isSoloed = soloNodes.contains(id.index)
        let hasLayerChanges = !hiddenNodes.isEmpty || !soloNodes.isEmpty
        Button(isHidden ? "Show" : "Hide") { onToggleHidden(id.index) }
            .disabled(state == .hiddenInFile || state == .hiddenByParent)
        Button(isSoloed ? "Unsolo" : "Solo") { onToggleSolo(id.index) }
        Button("Frame") {
            if !selectedIDs.contains(id) { selection = id }
            onFrame(id.index)
        }
        Divider()
        Button("Show All") { onShowAll() }
            .disabled(!hasLayerChanges)
    }

    private func listSelection(in sections: [OutlinerSection]) -> Binding<Set<NodeID>> {
        Binding(
            get: { selectedIDs },
            set: { newIDs in
                selectedIDs = newIDs
                // Scene and camera rows act only when picked on their own.
                if newIDs.count == 1, let newID = newIDs.first, let item = Self.item(id: newID, in: sections) {
                    onActivate(item)
                }
            }
        )
    }

    private func isJoint(_ id: NodeID) -> Bool {
        id.kind.isSceneNode && document.isJoint(nodeIndex: id.index)
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
