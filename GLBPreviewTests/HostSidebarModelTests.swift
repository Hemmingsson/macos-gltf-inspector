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

    @Test func selectedCameraIndexDefaultsToFit() {
        var doc = GLTFSessionDocument()
        doc.cameras = [
            .init(name: "Front", type: "perspective", yfov: 0.7, znear: 0.1, zfar: 100, xmag: nil, ymag: nil),
        ]
        let model = HostSidebarModel(document: doc)
        #expect(model.selectedCameraIndex == nil)
        model.selectedCameraIndex = 0
        #expect(model.selectedCameraIndex == 0)
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

    @MainActor
    @Test func roughnessThenNoneClearsDebugComponent() {
        let entity = Entity()
        entity.components.set(ModelComponent(mesh: MeshResource.generateBox(size: 0.1), materials: [PhysicallyBasedMaterial()]))

        let model = HostSidebarModel(document: GLTFSessionDocument())
        model.debug = .roughness
        model.overlayRevision += 1
        model.applyIfNeeded(to: entity)
        #expect(debugVisualization(entity) == .roughness)

        model.debug = .none
        model.overlayRevision += 1
        model.applyIfNeeded(to: entity)
        #expect(debugVisualization(entity) == nil)
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

private func entity(nodeIndex: Int, in root: Entity) -> Entity? {
    if root.components[GLTFNodeIDComponent.self]?.nodeIndex == nodeIndex {
        return root
    }
    for child in root.children {
        if let found = entity(nodeIndex: nodeIndex, in: child) {
            return found
        }
    }
    return nil
}

private func debugVisualization(_ entity: Entity) -> ModelDebugOptionsComponent.VisualizationMode? {
    if let mode = entity.components[ModelDebugOptionsComponent.self]?.visualizationMode {
        return mode
    }
    for child in entity.children {
        if let mode = debugVisualization(child) {
            return mode
        }
    }
    return nil
}

private func writeTempOneNodeMeshGLB(nodeName: String) throws -> URL {
    var bin = Data()
    for value: Float in [0, 0, 0, 1, 0, 0, 0, 1, 0] {
        var bits = value.bitPattern.littleEndian
        Swift.withUnsafeBytes(of: &bits) { bin.append(contentsOf: $0) }
    }
    let json: [String: Any] = [
        "asset": ["version": "2.0"],
        "buffers": [["byteLength": bin.count]],
        "bufferViews": [["buffer": 0, "byteOffset": 0, "byteLength": bin.count]],
        "accessors": [[
            "bufferView": 0,
            "componentType": 5126,
            "count": 3,
            "type": "VEC3",
        ]],
        "meshes": [["name": "HelmetMesh", "primitives": [["attributes": ["POSITION": 0]]]]],
        "nodes": [["name": nodeName, "mesh": 0]],
        "scenes": [["name": "Default", "nodes": [0]]],
        "scene": 0,
    ]
    let data = try GLBBox.serialize(json: json, bin: bin)
    return try GLBBox.writePrepared(data, prefix: "host-sidebar")
}
