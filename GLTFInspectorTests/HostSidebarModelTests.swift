import Foundation
@testable import GLTFCore
@testable import GLTFInspector
import Testing

/// Sidebar state. Applying it to RealityKit entities (`HostSidebarModel: PreviewOverlay`):
/// `RealityKit/HostSidebarModelOverlayTests.swift`.
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
}


private func testNode(index: Int, name: String, children: [Int]) -> GLTFSessionDocument.Node {
    .init(index: index, name: name, children: children, cameraIndex: nil)
}
