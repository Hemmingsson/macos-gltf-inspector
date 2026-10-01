import Foundation

/// Pure expand/collapse helpers for the Scene section — kept free of SwiftUI so fold behaviour
/// can be proved without driving a window.
public enum OutlinerTree {
    /// Full scene-graph tree preserving hierarchy for all authored node kinds.
    public static func fullRoots(_ nodes: [SceneNode]) -> [OutlinerItem] {
        nodes.map { node in
            OutlinerItem(id: node.id, name: node.name, children: fullRoots(node.children))
        }
    }

    /// Default: expand every node whose depth is strictly less than `maxDepth` (host uses 3).
    public static func defaultExpandedIDs(roots: [OutlinerItem], maxDepth: Int = 3) -> Set<NodeID> {
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
    public static func toggle(
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

    public static func isFullyExpanded(_ item: OutlinerItem, expanded: Set<NodeID>) -> Bool {
        guard !item.children.isEmpty else { return true }
        guard expanded.contains(item.id) else { return false }
        return item.children.allSatisfy { isFullyExpanded($0, expanded: expanded) }
    }

    public static func expandSubtree(_ item: OutlinerItem, expanded: inout Set<NodeID>) {
        guard !item.children.isEmpty else { return }
        expanded.insert(item.id)
        for child in item.children {
            expandSubtree(child, expanded: &expanded)
        }
    }

    public static func collapseSubtree(_ item: OutlinerItem, expanded: inout Set<NodeID>) {
        expanded.remove(item.id)
        for child in item.children {
            collapseSubtree(child, expanded: &expanded)
        }
    }

    /// Stable identity for “document / fixture tree changed” — reset expansion when this flips.
    public static func treeIdentity(_ roots: [OutlinerItem]) -> [NodeID] {
        var ids: [NodeID] = []
        func walk(_ item: OutlinerItem) {
            ids.append(item.id)
            item.children.forEach(walk)
        }
        roots.forEach(walk)
        return ids
    }
}
