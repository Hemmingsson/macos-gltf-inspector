import PreviewUI
import Testing
@testable import GLTFInspector

struct OutlinerTreeTests {
    private let root = OutlinerItem(
        id: NodeID(kind: .empty, index: 0),
        name: "Root",
        depth: 0,
        children: [
            OutlinerItem(
                id: NodeID(kind: .mesh, index: 0),
                name: "Mesh",
                depth: 1,
                children: [
                    OutlinerItem(
                        id: NodeID(kind: .mesh, index: 1),
                        name: "Child",
                        depth: 2
                    )
                ]
            )
        ]
    )

    @Test func defaultExpandedIDs_expandsShallowLevels() {
        let expanded = OutlinerTree.defaultExpandedIDs(roots: [root], maxDepth: 2)
        #expect(expanded.contains(root.id))
        #expect(expanded.contains(root.children[0].id))
        #expect(!expanded.contains(root.children[0].children[0].id))
    }

    @Test func toggle_plainClick_expandsAndCollapsesOneNode() {
        var expanded = Set<NodeID>()
        OutlinerTree.toggle(root, recursive: false, expanded: &expanded)
        #expect(expanded == [root.id])
        OutlinerTree.toggle(root, recursive: false, expanded: &expanded)
        #expect(expanded.isEmpty)
    }

    @Test func toggle_recursive_expandsWholeSubtree() {
        var expanded = Set<NodeID>()
        OutlinerTree.toggle(root, recursive: true, expanded: &expanded)
        #expect(OutlinerTree.isFullyExpanded(root, expanded: expanded))
    }

    @Test func toggle_recursive_collapsesFullyExpandedSubtree() {
        var expanded = OutlinerTree.defaultExpandedIDs(roots: [root], maxDepth: 10)
        OutlinerTree.toggle(root, recursive: true, expanded: &expanded)
        #expect(expanded.isEmpty)
    }

    @Test func treeIdentity_isStablePreorder() {
        let identity = OutlinerTree.treeIdentity([root])
        #expect(identity == [
            root.id,
            root.children[0].id,
            root.children[0].children[0].id
        ])
    }
}
