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

    /// Group 0 › mesh 1 › mesh 2, and mesh 3 beside the group.
    private var layers: [OutlinerItem] {
        let leaf = OutlinerItem(id: NodeID(kind: .mesh, index: 2), name: "Leaf")
        let mesh = OutlinerItem(id: NodeID(kind: .mesh, index: 1), name: "Mesh", children: [leaf])
        return [OutlinerItem(id: NodeID(kind: .empty, index: 0), name: "Group", children: [mesh]),
                OutlinerItem(id: NodeID(kind: .mesh, index: 3), name: "Other")]
    }

    private func state(_ index: Int, _ map: [NodeID: DSVisibility]) -> DSVisibility? {
        map.first { $0.key.index == index }?.value
    }

    @Test func layerVisibilityFollowsHideSoloAndTheFile() {
        let none = OutlinerTree.layerVisibility(layers, isHiddenInFile: { _ in false }, hidden: [], solo: [])
        #expect((0...3).allSatisfy { state($0, none) == .visible })

        let hidden = OutlinerTree.layerVisibility(layers, isHiddenInFile: { _ in false }, hidden: [0], solo: [])
        #expect(state(0, hidden) == .hidden)
        #expect(state(1, hidden) == .hiddenByParent && state(2, hidden) == .hiddenByParent)
        #expect(state(3, hidden) == .visible)

        let solo = OutlinerTree.layerVisibility(layers, isHiddenInFile: { _ in false }, hidden: [], solo: [1])
        #expect(state(0, solo) == .hiddenByParent)
        #expect(state(1, solo) == .visible && state(2, solo) == .visible)
        #expect(state(3, solo) == .hiddenByParent)

        let file = OutlinerTree.layerVisibility(layers, isHiddenInFile: { $0 == 1 }, hidden: [], solo: [])
        #expect(state(1, file) == .hiddenInFile && state(2, file) == .hiddenByParent)
    }

    @Test func pathToReturnsAncestorsThenSelf() {
        let leaf = NodeID(kind: .mesh, index: 2)
        #expect(OutlinerTree.path(to: leaf, in: layers) == [
            NodeID(kind: .empty, index: 0),
            NodeID(kind: .mesh, index: 1),
            leaf,
        ])
        let root = NodeID(kind: .empty, index: 0)
        #expect(OutlinerTree.path(to: root, in: layers) == [root])
        #expect(OutlinerTree.path(to: NodeID(kind: .mesh, index: 99), in: layers) == nil)
    }

    @Test func revealExpandsAncestorsWithoutCollapsingOthers() {
        let leaf = NodeID(kind: .mesh, index: 2)
        var expanded: Set<NodeID> = [NodeID(kind: .mesh, index: 3)]
        OutlinerTree.reveal(leaf, in: layers, expanded: &expanded)
        #expect(expanded.contains(NodeID(kind: .empty, index: 0)))
        #expect(expanded.contains(NodeID(kind: .mesh, index: 1)))
        #expect(expanded.contains(NodeID(kind: .mesh, index: 3)))
        #expect(!expanded.contains(leaf), "leaves are not expansion keys")
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

    @Test func sceneGraphListsOnlyTheActiveScenesRoots() {
        let document = GLTFDocumentJSON.makeDocument(json: [
            "scenes": [["nodes": [0]], ["nodes": [0, 2]]],
            "nodes": [["name": "Root", "children": [1]], ["mesh": 0], ["name": "Lamp"]],
            "meshes": [["primitives": [["attributes": ["POSITION": 0]]]]],
        ])
        let scene0 = OutlinerSection.sections(of: document, activeSceneIndex: 0).first { $0.title == "Scene" }
        #expect(scene0?.items.map(\.name) == ["Root"])
        #expect(scene0?.items.first?.children.map(\.id) == [NodeID(kind: .mesh, index: 1)])

        let scene1 = OutlinerSection.sections(of: document, activeSceneIndex: 1).first { $0.title == "Scene" }
        #expect(scene1?.items.map(\.name) == ["Root", "Lamp"])
    }
}
