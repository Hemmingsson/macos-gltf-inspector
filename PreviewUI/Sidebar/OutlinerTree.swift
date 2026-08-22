import Foundation

/// Indent / disclosure metrics for the Meshes outliner tree (ported from host `LayerOutlineMetrics`).
///
/// One step = arrow column + gap, so a child’s chevron left edge lines up under the parent’s title.
enum OutlinerTreeMetrics {
    static let arrow: CGFloat = 14
    static let gap: CGFloat = 4
    static var step: CGFloat { arrow + gap }
}

/// Pure expand/collapse helpers for the Meshes section — kept free of SwiftUI so fold behaviour
/// can be proved without driving a window.
enum OutlinerTree {
    /// Mesh-visible tree: skip non-mesh ancestors without a row, keep nesting among mesh rows.
    static func meshRoots(_ nodes: [SceneNode], depth: Int = 0) -> [OutlinerItem] {
        nodes.flatMap { node -> [OutlinerItem] in
            guard node.kind == .mesh else {
                return meshRoots(node.children, depth: depth)
            }
            let children = meshRoots(node.children, depth: depth + 1)
            return [
                OutlinerItem(id: node.id, name: node.name, depth: depth, children: children)
            ]
        }
    }

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
}
