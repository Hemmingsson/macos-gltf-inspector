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

        let model = try await EntityLoader.load(from: url, includeAnimations: false)
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

        let model = try await EntityLoader.load(from: url, includeAnimations: false)
        #expect(model.document.scenes.count == 2)
        #expect(model.document.defaultSceneIndex == 0)
        #expect(model.document.scenes[0].rootNodeIndices == [0])
        #expect(model.document.scenes[1].rootNodeIndices == [1])
        let stamped = stampedNodeIndices(in: model.entity)
        #expect(stamped.contains(0))
        #expect(!stamped.contains(1))
    }

    @MainActor
    @Test func lazyConvertSecondSceneStampsItsRoot() async throws {
        let twoSceneURL = try writeTempTwoSceneGLB()
        defer { try? FileManager.default.removeItem(at: twoSceneURL) }

        let other = try await EntityLoader.convertScene(
            index: 1,
            from: twoSceneURL,
            includeAnimations: true
        )
        #expect(stampedNodeIndices(in: other).contains(1))
    }

    @MainActor
    @Test func convertSceneOutOfRangeThrows1020() async throws {
        let url = try writeTempTwoSceneGLB()
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            _ = try await EntityLoader.convertScene(index: 99, from: url, includeAnimations: false)
            Issue.record("expected GLBPreviewError 1020")
        } catch {
            let nsError = error as NSError
            #expect(nsError.domain == GLBPreviewError.domain)
            #expect(nsError.code == 1020)
        }
    }

    @MainActor
    @Test func staticBoxHasNoAnimations() async throws {
        let url = try writeTempOneNodeMeshGLB(nodeName: "Box")
        defer { try? FileManager.default.removeItem(at: url) }

        let model = try await EntityLoader.load(from: url, includeAnimations: true)
        #expect(model.document.animations.isEmpty)
        #expect(model.entity.availableAnimations.isEmpty)
    }

    @MainActor
    @Test func documentAnimationsMatchUsableClips() async throws {
        let url = try writeTempTwoClipGLB()
        defer { try? FileManager.default.removeItem(at: url) }

        let model = try await EntityLoader.load(from: url, includeAnimations: true)
        #expect(model.document.animations.count == 2)
        #expect(model.document.animations.count == model.entity.availableAnimations.count)
        #expect(model.document.animations[0].name == "ClipA")
        #expect(model.document.animations[1].name == "ClipB")
        #expect(model.document.animations[0].duration > 0)
        #expect(model.document.animations[1].duration > 0)
        #expect(model.document.animations[1].duration >= model.document.animations[0].duration)
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

private func writeTempTwoClipGLB() throws -> URL {
    var bin = triangleBin()
    let positionLength = bin.count
    appendFloats([0, 1], to: &bin)
    let timeALength = 8
    appendFloats([0, 0, 0, 1, 0, 0], to: &bin)
    let transALength = 24
    appendFloats([0, 2], to: &bin)
    let timeBLength = 8
    appendFloats([0, 0, 0, 0, 1, 0], to: &bin)
    let transBLength = 24
    let timeAOffset = positionLength
    let transAOffset = timeAOffset + timeALength
    let timeBOffset = transAOffset + transALength
    let transBOffset = timeBOffset + timeBLength
    let json: [String: Any] = [
        "asset": ["version": "2.0"],
        "buffers": [["byteLength": bin.count]],
        "bufferViews": [
            ["buffer": 0, "byteOffset": 0, "byteLength": positionLength],
            ["buffer": 0, "byteOffset": timeAOffset, "byteLength": timeALength],
            ["buffer": 0, "byteOffset": transAOffset, "byteLength": transALength],
            ["buffer": 0, "byteOffset": timeBOffset, "byteLength": timeBLength],
            ["buffer": 0, "byteOffset": transBOffset, "byteLength": transBLength],
        ],
        "accessors": [
            [
                "bufferView": 0,
                "componentType": 5126,
                "count": 3,
                "type": "VEC3",
            ],
            [
                "bufferView": 1,
                "componentType": 5126,
                "count": 2,
                "type": "SCALAR",
                "min": [0.0],
                "max": [1.0],
            ],
            [
                "bufferView": 2,
                "componentType": 5126,
                "count": 2,
                "type": "VEC3",
            ],
            [
                "bufferView": 3,
                "componentType": 5126,
                "count": 2,
                "type": "SCALAR",
                "min": [0.0],
                "max": [2.0],
            ],
            [
                "bufferView": 4,
                "componentType": 5126,
                "count": 2,
                "type": "VEC3",
            ],
        ],
        "meshes": [["name": "Mesh", "primitives": [["attributes": ["POSITION": 0]]]]],
        "nodes": [["name": "Root", "mesh": 0]],
        "animations": [
            [
                "name": "ClipA",
                "samplers": [["input": 1, "output": 2, "interpolation": "LINEAR"]],
                "channels": [["sampler": 0, "target": ["node": 0, "path": "translation"]]],
            ],
            [
                "name": "ClipB",
                "samplers": [["input": 3, "output": 4, "interpolation": "LINEAR"]],
                "channels": [["sampler": 0, "target": ["node": 0, "path": "translation"]]],
            ],
        ],
        "scenes": [["name": "Default", "nodes": [0]]],
        "scene": 0,
    ]
    return try writeTempGLB(json: json, bin: bin)
}

private func writeTempGLB(json: [String: Any], bin: Data) throws -> URL {
    let data = try GLBBox.serialize(json: json, bin: bin)
    return try GLBBox.writePrepared(data, prefix: "session-doc")
}
