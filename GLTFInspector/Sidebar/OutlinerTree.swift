import Foundation

/// Pure expand/collapse helpers for the Scene section — kept free of SwiftUI so fold behaviour
/// can be proved without driving a window.
enum OutlinerTree {
    /// Default: expand every node whose depth is strictly less than `maxDepth` (host uses 3).
    static func defaultExpandedIDs(roots: [OutlinerItem], maxDepth: Int = 3) -> Set<NodeID> {
        var ids = Set<NodeID>()
        func walk(_ item: OutlinerItem, depth: Int) {
            if depth < maxDepth {
                ids.insert(item.id)
            }
            for child in item.children {
                walk(child, depth: depth + 1)
            }
        }
        roots.forEach { walk($0, depth: 0) }
        return ids
    }

    /// One visible row of a flattened tree: the item and how deep it sits.
    struct Row: Identifiable, Hashable, Sendable {
        var item: OutlinerItem
        var depth: Int
        /// Tree guide lines, one per indent level (`depth` entries). Entry `k` says whether the
        /// row's ancestor at depth `k + 1` (the row itself for the last entry) has a sibling
        /// after it, so the vertical guide at that level continues below this row.
        var guides: [Bool] = []
        var id: NodeID { item.id }
    }

    /// Rows a reader sees, depth-first: an item's children follow it only while it is expanded.
    static func visibleRows(_ roots: [OutlinerItem], expanded: Set<NodeID>) -> [Row] {
        var rows: [Row] = []
        func walk(_ item: OutlinerItem, depth: Int, guides: [Bool]) {
            rows.append(Row(item: item, depth: depth, guides: guides))
            guard expanded.contains(item.id) else { return }
            for (index, child) in item.children.enumerated() {
                walk(child, depth: depth + 1, guides: guides + [index < item.children.count - 1])
            }
        }
        roots.forEach { walk($0, depth: 0, guides: []) }
        return rows
    }

    /// Plain click toggles one node; Option-click expands/collapses the whole subtree.
    /// If open but not fully expanded, Option-click finishes expanding (does not collapse).
    static func toggle(
        _ item: OutlinerItem,
        recursive: Bool,
        expanded: inout Set<NodeID>
    ) {
        if recursive {
            if expanded.contains(item.id), isFullyExpanded(item, expanded: expanded) {
                collapseSubtree(item, expanded: &expanded)
            } else {
                expandSubtree(item, expanded: &expanded)
            }
        } else if expanded.contains(item.id) {
            expanded.remove(item.id)
        } else {
            expanded.insert(item.id)
        }
    }

    static func isFullyExpanded(_ item: OutlinerItem, expanded: Set<NodeID>) -> Bool {
        guard !item.children.isEmpty else { return true }
        guard expanded.contains(item.id) else { return false }
        return item.children.allSatisfy { isFullyExpanded($0, expanded: expanded) }
    }

    static func expandSubtree(_ item: OutlinerItem, expanded: inout Set<NodeID>) {
        guard !item.children.isEmpty else { return }
        expanded.insert(item.id)
        for child in item.children {
            expandSubtree(child, expanded: &expanded)
        }
    }

    static func collapseSubtree(_ item: OutlinerItem, expanded: inout Set<NodeID>) {
        expanded.remove(item.id)
        for child in item.children {
            collapseSubtree(child, expanded: &expanded)
        }
    }

    /// The layer state of every scene-graph row, as the renderer will draw it: a node's own
    /// authored or window hide wins, then any hidden ancestor, then solo (only soloed nodes and
    /// their subtrees draw). `hidden` and `solo` are glTF node indices.
    static func layerVisibility(
        _ roots: [OutlinerItem],
        isHiddenInFile: (Int) -> Bool,
        hidden: Set<Int>,
        solo: Set<Int>
    ) -> [NodeID: DSVisibility] {
        var result: [NodeID: DSVisibility] = [:]
        /// `ancestorHidden`: an ancestor hides its subtree. `soloed`: self or an ancestor is soloed.
        func walk(_ item: OutlinerItem, ancestorHidden: Bool, soloed: Bool) {
            let index = item.id.index
            let ownHiddenInFile = isHiddenInFile(index)
            let ownHidden = hidden.contains(index)
            let isSoloed = soloed || solo.contains(index)
            let state: DSVisibility
            if ownHiddenInFile {
                state = .hiddenInFile
            } else if ownHidden {
                state = .hidden
            } else if ancestorHidden || (!solo.isEmpty && !isSoloed) {
                state = .hiddenByParent
            } else {
                state = .visible
            }
            result[item.id] = state
            let childrenHidden = ancestorHidden || ownHidden || ownHiddenInFile
            for child in item.children {
                walk(child, ancestorHidden: childrenHidden, soloed: isSoloed)
            }
        }
        roots.forEach { walk($0, ancestorHidden: false, soloed: false) }
        return result
    }

    /// Stable identity for “document / fixture tree changed” — reset expansion when this flips.
    static func treeIdentity(_ roots: [OutlinerItem]) -> [NodeID] {
        var ids: [NodeID] = []
        func walk(_ item: OutlinerItem) {
            ids.append(item.id)
            item.children.forEach(walk)
        }
        roots.forEach(walk)
        return ids
    }

    /// Root → … → `id`, or nil when `id` is not in the tree. Includes `id` itself.
    static func path(to id: NodeID, in roots: [OutlinerItem]) -> [NodeID]? {
        func walk(_ items: [OutlinerItem], trail: [NodeID]) -> [NodeID]? {
            for item in items {
                let next = trail + [item.id]
                if item.id == id { return next }
                if let found = walk(item.children, trail: next) { return found }
            }
            return nil
        }
        return walk(roots, trail: [])
    }

    /// Expands every ancestor of `id` so the row is visible. Leaves unrelated expansion alone.
    static func reveal(_ id: NodeID, in roots: [OutlinerItem], expanded: inout Set<NodeID>) {
        guard let path = path(to: id, in: roots), path.count > 1 else { return }
        for ancestor in path.dropLast() {
            expanded.insert(ancestor)
        }
    }
}
