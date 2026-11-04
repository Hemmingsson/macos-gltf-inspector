import Foundation
@testable import GLTFCore
@testable import GLTFInspector
import PreviewUI
import Renderer
import Testing

/// Sidebar state, and how it reaches the page `Look`.
@MainActor
struct HostSidebarModelTests {
    @Test func sceneChangeClearsTheSelectedNode() {
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
        model.selectedNodeIndex = 0

        model.activeSceneIndex = 0
        #expect(model.selectedNodeIndex == 0)

        model.activeSceneIndex = 1
        #expect(model.selectedNodeIndex == nil)
    }

    /// The outliner's camera row is the scene-tree node (its id is the node index, not the index in
    /// `cameras`), and the page frames from that node.
    @Test func fileCameraReachesTheLookAsItsNodeIndex() throws {
        var doc = GLTFSessionDocument()
        doc.cameras = [
            .init(name: "Cam", type: "perspective", yfov: 1, znear: 0.1, zfar: 100, xmag: nil, ymag: nil),
        ]
        doc.nodes = [
            testNode(index: 0, name: "Root", children: [3]),
            .init(index: 3, name: "CamNode", children: [], kind: .camera, cameraIndex: 0),
        ]
        doc.scenes = [.init(name: "A", rootNodeIndices: [0]), .init(name: "B", rootNodeIndices: [])]
        let sidebar = HostSidebarModel(document: doc)
        let viewport = EngineViewportController(sidebar: sidebar)

        #expect(ViewOptions(viewport, sidebar: sidebar) == ViewOptions(viewport, sidebar: nil))

        let model = EngineSceneModel(
            fileName: "cam.gltf", document: doc,
            dimensions: Dimensions(width: 0, height: 0, depth: 0, authoredOrigin: .zero)
        )
        let cameraID = try #require(
            OutlinerSection.sections(of: model).flatMap { OutlinerTree.treeIdentity($0.items) }
                .first { $0.kind == .camera }
        )
        viewport.setFileCamera(cameraID)
        #expect(
            ViewOptions(viewport, sidebar: sidebar)
                == ViewOptions(viewport, sceneIndex: 0, fileCameraNodeIndex: 3)
        )
        #expect(EngineSelectionModel.detail(for: cameraID, document: doc)?.camera?.name == "Cam")

        // A scene switch drops the file camera with the selection.
        sidebar.activeSceneIndex = 1
        #expect(sidebar.selectedCameraNodeIndex == nil)
    }
}

private func testNode(index: Int, name: String, children: [Int]) -> GLTFSessionDocument.Node {
    .init(index: index, name: name, children: children, cameraIndex: nil)
}
