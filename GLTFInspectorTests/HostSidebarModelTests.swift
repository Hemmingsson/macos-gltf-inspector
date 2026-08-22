import Foundation
import RealityKit
import Testing
import simd
@testable import GLTFInspector

@MainActor
struct HostSidebarModelTests {
    @Test func layerRootIndicesFollowActiveScene() {
        var doc = GLTFSessionDocument()
        doc.scenes = [
            .init(name: "A", rootNodeIndices: [0]),
            .init(name: "B", rootNodeIndices: [1]),
        ]
        doc.nodes = [
            testNode(index: 0, name: "RootA", children: []),
            testNode(index: 1, name: "RootB", children: []),
        ]
        let model = HostSidebarModel(document: doc)
        model.activeSceneIndex = 0
        #expect(model.layerRootIndices() == [0])
        model.activeSceneIndex = 1
        #expect(model.layerRootIndices() == [1])
    }

    @Test func showAllClearsHideAndSolo() {
        let model = HostSidebarModel(document: .init())
        model.hide = [0, 1]
        model.soloRoot = 0
        model.showAll()
        #expect(model.hide.isEmpty)
        #expect(model.soloRoot == nil)
    }

    @Test func isolateTogglesSameNode() {
        let model = HostSidebarModel(document: .init())
        model.isolate(3)
        #expect(model.soloRoot == 3)
        model.isolate(3)
        #expect(model.soloRoot == nil)
    }

    @Test func isolateClearsOnSceneChange() {
        var doc = GLTFSessionDocument()
        doc.scenes = [
            .init(name: "A", rootNodeIndices: [0]),
            .init(name: "B", rootNodeIndices: [1]),
        ]
        doc.nodes = [
            testNode(index: 0, name: "RootA", children: []),
            testNode(index: 1, name: "RootB", children: []),
        ]
        let model = HostSidebarModel(document: doc)
        model.activeSceneIndex = 0
        model.isolate(0)
        #expect(model.soloRoot == 0)
        model.activeSceneIndex = 1
        #expect(model.soloRoot == nil)
    }

    @Test func selectNodeTogglesAndClearsOnSceneChange() {
        var doc = GLTFSessionDocument()
        doc.scenes = [
            .init(name: "A", rootNodeIndices: [0]),
            .init(name: "B", rootNodeIndices: [1]),
        ]
        doc.nodes = [
            testNode(index: 0, name: "RootA", children: []),
            testNode(index: 1, name: "RootB", children: []),
        ]
        let model = HostSidebarModel(document: doc)
        model.activeSceneIndex = 0
        let before = model.overlayRevision

        model.selectNode(0)
        #expect(model.selectedNodeIndex == 0)
        #expect(model.overlayRevision == before + 1)

        model.selectNode(0)
        #expect(model.selectedNodeIndex == nil)

        model.selectNode(0)
        model.activeSceneIndex = 1
        #expect(model.selectedNodeIndex == nil)
    }

    @MainActor
    @Test func selectionDimsOthersAddsBoxAndClears() async throws {
        let mesh = MeshResource.generateBox(size: 0.2)
        let material = SimpleMaterial()

        let root = Entity()
        let node0 = Entity()
        let node1 = Entity()
        node0.name = "Selected"
        node1.name = "Other"
        node0.components.set(GLTFNodeIDComponent(nodeIndex: 0))
        node1.components.set(GLTFNodeIDComponent(nodeIndex: 1))
        node0.components.set(ModelComponent(mesh: mesh, materials: [material]))
        node1.components.set(ModelComponent(mesh: mesh, materials: [material]))
        root.addChild(node0)
        root.addChild(node1)

        var doc = GLTFSessionDocument()
        doc.scenes = [.init(name: "A", rootNodeIndices: [0, 1])]
        doc.nodes = [
            testNode(index: 0, name: "Selected", children: []),
            testNode(index: 1, name: "Other", children: []),
        ]
        let model = HostSidebarModel(document: doc)

        model.selectNode(0)
        model.applyIfNeeded(to: root)

        #expect(node0.components[OpacityComponent.self] == nil)
        #expect(node1.components[OpacityComponent.self]?.opacity == PreviewSelectionVisuals.dimOpacity)
        #expect(node0.children.contains(where: { $0.name == PreviewFloor.selectionBoxName }))
        #expect(node0.components.has(HoverEffectComponent.self))
        #expect(node0.components.has(InputTargetComponent.self))
        #expect(node0.components.has(CollisionComponent.self))

        model.selectNode(0)
        model.applyIfNeeded(to: root)
        #expect(node0.components[OpacityComponent.self] == nil)
        #expect(node1.components[OpacityComponent.self] == nil)
        #expect(!node0.children.contains(where: { $0.name == PreviewFloor.selectionBoxName }))
        #expect(!node0.components.has(HoverEffectComponent.self))
        #expect(!node0.components.has(InputTargetComponent.self))
        #expect(!node0.components.has(CollisionComponent.self))
    }

    @MainActor
    @Test func hideStillDisablesSelectedEntity() async throws {
        let url = try writeTempOneNodeMeshGLB(nodeName: "Mesh")
        defer { try? FileManager.default.removeItem(at: url) }

        let loaded = try await EntityLoader.load(from: url, includeAnimations: false)
        let model = HostSidebarModel(document: loaded.document)
        model.selectNode(0)
        model.hide.insert(0)
        model.overlayRevision += 1
        model.applyIfNeeded(to: loaded.entity)
        #expect(entity(nodeIndex: 0, in: loaded.entity)?.isEnabled == false)
    }

    @MainActor
    @Test func hideDisablesMappedEntity() async throws {
        let url = try writeTempOneNodeMeshGLB(nodeName: "Mesh")
        defer { try? FileManager.default.removeItem(at: url) }

        let loaded = try await EntityLoader.load(from: url, includeAnimations: false)
        let model = HostSidebarModel(document: loaded.document)
        model.hide.insert(0)
        model.overlayRevision += 1
        model.applyIfNeeded(to: loaded.entity)
        #expect(entity(nodeIndex: 0, in: loaded.entity)?.isEnabled == false)
    }

    @MainActor
    @Test func isolateKeepsSubtreeAndAncestorsHidesSiblings() {
        // Multi-node graph: two scene roots; RootA → ChildA / SiblingA.
        var doc = GLTFSessionDocument()
        doc.scenes = [.init(name: "A", rootNodeIndices: [0, 1])]
        doc.nodes = [
            testNode(index: 0, name: "RootA", children: [2, 3]),
            testNode(index: 1, name: "RootB", children: []),
            testNode(index: 2, name: "ChildA", children: [4]),
            testNode(index: 3, name: "SiblingA", children: []),
            testNode(index: 4, name: "Grandchild", children: []),
        ]
        let model = HostSidebarModel(document: doc)

        let root = Entity()
        let nodes = (0...4).map { index -> Entity in
            let e = Entity()
            e.components.set(GLTFNodeIDComponent(nodeIndex: index))
            return e
        }
        nodes[0].addChild(nodes[2])
        nodes[0].addChild(nodes[3])
        nodes[2].addChild(nodes[4])
        root.addChild(nodes[0])
        root.addChild(nodes[1])

        model.isolate(2)
        model.applyIfNeeded(to: root)

        #expect(nodes[0].isEnabled == true)  // ancestor
        #expect(nodes[1].isEnabled == false) // other scene root
        #expect(nodes[2].isEnabled == true)  // solo root
        #expect(nodes[3].isEnabled == false) // sibling
        #expect(nodes[4].isEnabled == true)  // descendant
        #expect(model.soloHides(0) == false)
        #expect(model.soloHides(1) == true)
        #expect(model.soloHides(2) == false)
        #expect(model.soloHides(3) == true)
        #expect(model.soloHides(4) == false)

        model.showAll()
        model.applyIfNeeded(to: root)
        #expect(model.soloRoot == nil)
        #expect(nodes.allSatisfy { $0.isEnabled })
    }

}

private func testNode(index: Int, name: String, children: [Int]) -> GLTFSessionDocument.Node {
    .init(index: index, name: name, children: children, cameraIndex: nil)
}
