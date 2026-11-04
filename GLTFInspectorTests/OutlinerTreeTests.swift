@testable import GLTFCore
import Testing
@testable import GLTFInspector

struct OutlinerTreeTests {
    private let root = OutlinerItem(
        id: NodeID(kind: .empty, index: 0),
        name: "Root",
        children: [
            OutlinerItem(
                id: NodeID(kind: .mesh, index: 0),
                name: "Mesh",
                children: [
                    OutlinerItem(
                        id: NodeID(kind: .mesh, index: 1),
                        name: "Child"
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

    @Test func visibleRows_followExpansionWithDepth() {
        #expect(OutlinerTree.visibleRows([root], expanded: []).map(\.id) == [root.id])

        let rows = OutlinerTree.visibleRows([root], expanded: [root.id])
        #expect(rows.map(\.id) == [root.id, root.children[0].id])
        #expect(rows.map(\.depth) == [0, 1])

        let all = OutlinerTree.visibleRows([root], expanded: [root.id, root.children[0].id])
        #expect(all.map(\.depth) == [0, 1, 2])
    }
}

/// The sidebar's sections, from the parsed document.
struct OutlinerSectionTests {
    @Test func clipsWithoutADurationAreLeftOutButKeepTheirIndex() {
        var document = GLTFDocument()
        document.animations = [.init(name: "Junk", duration: 0), .init(name: "Walk", duration: 1.5)]
        let animations = OutlinerSection.sections(of: document).first { $0.title == "Animations" }
        #expect(animations?.items.map(\.id) == [NodeID(kind: .animation, index: 1)])
        #expect(animations?.items.map(\.name) == ["Walk"])
    }

    @Test func sceneGraphListsEveryScenesRootsOnceWithChildren() {
        let document = GLTFDocumentJSON.makeDocument(json: [
            "scenes": [["nodes": [0]], ["nodes": [0, 2]]],
            "nodes": [["name": "Root", "children": [1]], ["mesh": 0], ["name": "Lamp"]],
            "meshes": [["primitives": [["attributes": ["POSITION": 0]]]]],
        ])
        let graph = OutlinerSection.sections(of: document).first { $0.title == "Scene" }
        #expect(graph?.items.map(\.name) == ["Root", "Lamp"])
        #expect(graph?.items.first?.children.map(\.id) == [NodeID(kind: .mesh, index: 1)])
        #expect(graph?.items.first?.children.first?.name == "Node 1")
    }
}
