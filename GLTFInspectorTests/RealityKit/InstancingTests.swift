import CoreGraphics
import Foundation
@testable import GLTFCore
import RealityKit
@testable import RendererRealityKit
import Testing

/// `EXT_mesh_gpu_instancing` → one child entity per instance under the node, sharing the node's
/// `ModelComponent`. Instances are not document nodes, so they follow the node's hide/solo.
@MainActor
struct InstancingTests {
    @Test func instancesRenderLikeSeparateNodes() async throws {
        let instanced = try await loadModel(try instancedGLB(count: 3))
        let separate = try await loadModel(try separateNodesGLB(count: 3))
        let eye: SIMD3<Float> = [1.5, 0.5, 4]
        let a = try await PrepareFreeInputsTests.render(instanced.entity, eye: eye)
        let b = try await PrepareFreeInputsTests.render(separate.entity, eye: eye)
        #expect(try PrepareFreeInputsTests.meanDifference(a, b) < 0.05)
        #expect(instanced.document.nodes.count == 1)
        #expect(EntityLoader.modelComponentCount(in: instanced.entity) == 3)
    }

    @Test func hidingTheNodeHidesEveryInstance() async throws {
        let model = try await loadModel(try instancedGLB(count: 3))
        let node = try #require(GLTFNodeLookup.entity(nodeIndex: 0, in: model.entity))
        let eye: SIMD3<Float> = [1.5, 0.5, 4]
        let empty = try await PrepareFreeInputsTests.render(Entity(), eye: eye)
        #expect(try PrepareFreeInputsTests.meanDifference(try await PrepareFreeInputsTests.render(model.entity, eye: eye), empty) > 0.3)
        node.isEnabled = false
        #expect(try PrepareFreeInputsTests.meanDifference(try await PrepareFreeInputsTests.render(model.entity, eye: eye), empty) < 0.01)
    }
}

/// The same triangle as `instancedGLB`, as `count` plain nodes translated along X.
private func separateNodesGLB(count: Int) throws -> Data {
    let bin = floatTriangleBin()
    let json: [String: Any] = [
        "asset": ["version": "2.0"],
        "buffers": [["byteLength": bin.count]],
        "bufferViews": [["buffer": 0, "byteOffset": 0, "byteLength": bin.count]],
        "accessors": [["bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3"]],
        "meshes": [["primitives": [["attributes": ["POSITION": 0]]]]],
        "nodes": (0..<count).map { ["mesh": 0, "translation": [Double($0), 0, 0]] },
        "scenes": [["nodes": Array(0..<count)]],
        "scene": 0,
    ]
    return try TestGLB.serialize(json: json, bin: bin)
}
