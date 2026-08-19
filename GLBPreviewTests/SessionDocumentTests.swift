import Foundation
import RealityKit
import Testing
@testable import GLBPreview

struct SessionDocumentTests {
    @Test func nodeIDComponentRoundTrips() {
        let entity = Entity()
        entity.components.set(GLTFNodeIDComponent(nodeIndex: 3))
        #expect(entity.components[GLTFNodeIDComponent.self]?.nodeIndex == 3)
    }

    @Test func emptyDocumentHasNoScenes() {
        let doc = GLTFSessionDocument()
        #expect(doc.scenes.isEmpty)
        #expect(doc.defaultSceneIndex == 0)
    }

    @MainActor
    @Test func convertStampsNodeIndexZero() async throws {
        let url = try writeTempOneNodeMeshGLB(nodeName: "Helmet")
        defer { try? FileManager.default.removeItem(at: url) }

        let model = try await GLBEntityLoader.load(from: url, includeAnimations: false)
        #expect(stampedNodeIndices(in: model.entity).contains(0))
        #expect(model.document.nodes.contains { $0.name == "Helmet" || $0.meshIndex != nil })
        #expect(model.document.scenes.count >= 1)
        #expect(model.document.defaultSceneIndex == 0)
        #expect(model.document.scenes[model.document.defaultSceneIndex].rootNodeIndices.contains(0))
    }

    @MainActor
    @Test func documentListsEverySceneFromAsset() async throws {
        let url = try writeTempTwoSceneGLB()
        defer { try? FileManager.default.removeItem(at: url) }

        let model = try await GLBEntityLoader.load(from: url, includeAnimations: false)
        #expect(model.document.scenes.count == 2)
        #expect(model.document.defaultSceneIndex == 0)
        #expect(model.document.scenes[0].rootNodeIndices == [0])
        #expect(model.document.scenes[1].rootNodeIndices == [1])
        let stamped = stampedNodeIndices(in: model.entity)
        #expect(stamped.contains(0))
        #expect(!stamped.contains(1))
    }
}

private func stampedNodeIndices(in entity: Entity) -> Set<Int> {
    var found = Set<Int>()
    func walk(_ e: Entity) {
        if let id = e.components[GLTFNodeIDComponent.self]?.nodeIndex {
            found.insert(id)
        }
        e.children.forEach(walk)
    }
    walk(entity)
    return found
}

private func triangleBin() -> Data {
    var bin = Data()
    for value: Float in [0, 0, 0, 1, 0, 0, 0, 1, 0] {
        var bits = value.bitPattern.littleEndian
        Swift.withUnsafeBytes(of: &bits) { bin.append(contentsOf: $0) }
    }
    return bin
}

private func writeTempOneNodeMeshGLB(nodeName: String) throws -> URL {
    let bin = triangleBin()
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
    return try writeTempGLB(json: json, bin: bin)
}

private func writeTempTwoSceneGLB() throws -> URL {
    let bin = triangleBin()
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
        "meshes": [
            ["name": "MeshA", "primitives": [["attributes": ["POSITION": 0]]]],
            ["name": "MeshB", "primitives": [["attributes": ["POSITION": 0]]]],
        ],
        "nodes": [
            ["name": "RootA", "mesh": 0],
            ["name": "RootB", "mesh": 1],
        ],
        "scenes": [
            ["name": "SceneA", "nodes": [0]],
            ["name": "SceneB", "nodes": [1]],
        ],
        "scene": 0,
    ]
    return try writeTempGLB(json: json, bin: bin)
}

private func writeTempGLB(json: [String: Any], bin: Data) throws -> URL {
    let data = try GLBBox.serialize(json: json, bin: bin)
    return try GLBBox.writePrepared(data, prefix: "session-doc")
}
