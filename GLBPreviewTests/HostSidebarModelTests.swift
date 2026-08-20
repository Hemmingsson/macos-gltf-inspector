import Foundation
import RealityKit
import Testing
import simd
@testable import GLBPreview

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
    @Test func soloDisablesOtherSceneRootsNotAncestors() {
        var doc = GLTFSessionDocument()
        doc.scenes = [.init(name: "A", rootNodeIndices: [0, 1])]
        doc.nodes = [
            testNode(index: 0, name: "RootA", children: [2]),
            testNode(index: 1, name: "RootB", children: []),
            testNode(index: 2, name: "Child", children: []),
        ]
        let model = HostSidebarModel(document: doc)

        let root = Entity()
        let node0 = Entity()
        let node1 = Entity()
        let node2 = Entity()
        node0.components.set(GLTFNodeIDComponent(nodeIndex: 0))
        node1.components.set(GLTFNodeIDComponent(nodeIndex: 1))
        node2.components.set(GLTFNodeIDComponent(nodeIndex: 2))
        node0.addChild(node2)
        root.addChild(node0)
        root.addChild(node1)

        model.soloRoot = 0
        model.overlayRevision += 1
        model.applyIfNeeded(to: root)
        #expect(node0.isEnabled == true)
        #expect(node1.isEnabled == false)
        #expect(node2.isEnabled == true)
        #expect(model.soloHides(0) == false)
        #expect(model.soloHides(1) == true)
        #expect(model.soloHides(2) == false)

        model.soloRoot = 2
        model.overlayRevision += 1
        model.applyIfNeeded(to: root)
        #expect(node2.isEnabled == true)
        #expect(node0.isEnabled == true)
        #expect(node1.isEnabled == false)
    }
}

private func testNode(index: Int, name: String, children: [Int]) -> GLTFSessionDocument.Node {
    .init(
        index: index,
        name: name,
        children: children,
        meshIndex: nil,
        cameraIndex: nil,
        lightIndex: nil,
        translation: .zero,
        rotation: SIMD4<Float>(0, 0, 0, 1),
        scale: .one
    )
}
