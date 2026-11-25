import Foundation
import GLTFCore
import GLTFKit2
import Metal
import simd
import Testing
@testable import Renderer

struct MetalSceneLoaderTests {
    private func device() throws -> any MTLDevice { try #require(MTLCreateSystemDefaultDevice()) }

    @Test(arguments: [TestFixtures.tiny, TestFixtures.cube, TestFixtures.rigged, TestFixtures.morph])
    func fixtureContainsFiniteGeometry(url: URL) async throws {
        let scene = try await MetalSceneLoader.load(url:url,device:device())
        #expect(!scene.draws.isEmpty)
        #expect(scene.boundsMin.x.isFinite && scene.boundsMax.x.isFinite)
        #expect(all(scene.boundsMin .<= scene.boundsMax))
        for draw in scene.draws {
            #expect(draw.indexCount > 0)
            #expect(draw.vertexBuffer.length % MemoryLayout<MetalVertex>.stride == 0)
            #expect(draw.indexBuffer.length == draw.indexCount * 4)
        }
    }

    @Test func selectedSceneChangesDrawnNodes() async throws {
        let gpu = try device()
        let first = try await MetalSceneLoader.load(url:TestFixtures.multiScene,device:gpu,sceneIndex:0)
        let second = try await MetalSceneLoader.load(url:TestFixtures.multiScene,device:gpu,sceneIndex:1)
        #expect(first.draws.map(\.nodeIndex) == [0])
        #expect(second.draws.map(\.nodeIndex) == [1])
        await #expect(throws:(any Error).self) {
            _ = try await MetalSceneLoader.load(url:TestFixtures.multiScene,device:gpu,sceneIndex:999)
        }
    }

    @Test(arguments: ["integer expansion", "vertex expansion"])
    func expandedStorageIsRejectedBeforeLoading(kind: String) throws {
        let accessor: [String: Any] = kind == "integer expansion"
            ? ["componentType": 5121, "count": 70_000_000, "type": "SCALAR"]
            : ["componentType": 5126, "count": 4_000_000, "type": "VEC3"]
        let json: [String: Any] = [
            "asset": ["version": "2.0"], "accessors": [accessor],
            "meshes": [["primitives": [["attributes": ["POSITION": 0]]]]],
        ]
        let url = try TestGLB.writeTemp(try TestGLB.serialize(json: json, bin: Data()), prefix: "expanded-storage")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: MetalSceneError.self) { try MetalMeshoptPreprocessor.preflight(url: url) }
    }

    @Test func corruptFileIsRejected() async throws {
        let gpu = try device()
        await #expect(throws:(any Error).self) {
            _ = try await MetalSceneLoader.load(url:TestFixtures.corrupt,device:gpu)
        }
    }

    @Test func accessorPackingRejectsBufferViewOutsideItsBuffer() throws {
        let buffer = GLTFBuffer(data: Data(repeating: 0, count: 12))
        let view = GLTFBufferView(buffer: buffer, length: 12, offset: 8, stride: 0)
        let accessor = GLTFAccessor(
            bufferView: view,
            offset: 0,
            componentType: .float,
            dimension: .vector3,
            count: 1,
            normalized: false
        )

        #expect(throws: GLTFAccessorDataError.self) {
            try GLTFAccessorData.packed(accessor)
        }
    }

    @Test func accessorPackingZeroFillsBufferViewlessAccessor() throws {
        let accessor = GLTFAccessor(
            bufferView: nil, offset: 0, componentType: .float,
            dimension: .vector3, count: 2, normalized: false
        )
        #expect(try GLTFAccessorData.packed(accessor) == Data(repeating: 0, count: 24))
    }

    @Test func accessorPackingRejectsSparseIndexOutsideAccessor() throws {
        let indicesBuffer = GLTFBuffer(data: Data([2]))
        let valuesBuffer = GLTFBuffer(data: Data(repeating: 0, count: 12))
        let indices = GLTFBufferView(buffer: indicesBuffer, length: 1, offset: 0, stride: 0)
        let values = GLTFBufferView(buffer: valuesBuffer, length: 12, offset: 0, stride: 0)
        let sparse = GLTFSparseStorage(values: values, valueOffset: 0, indices: indices,
                                       indexOffset: 0, indexComponentType: .unsignedByte, count: 1)
        let accessor = GLTFAccessor(bufferView: nil, offset: 0, componentType: .float,
                                    dimension: .vector3, count: 2, normalized: false)
        accessor.sparse = sparse
        #expect(throws: GLTFAccessorDataError.self) { try GLTFAccessorData.packed(accessor) }
    }

    @Test(arguments: [GLTFComponentType.byte, .short, .float])
    func accessorPackingRejectsUnsupportedSparseIndexType(type: GLTFComponentType) throws {
        let indices = GLTFBufferView(buffer: GLTFBuffer(data: Data(repeating: 0, count: 4)),
                                     length: 4, offset: 0, stride: 0)
        let values = GLTFBufferView(buffer: GLTFBuffer(data: Data(repeating: 0, count: 4)),
                                    length: 4, offset: 0, stride: 0)
        let accessor = GLTFAccessor(bufferView: nil, offset: 0, componentType: .float,
                                    dimension: .scalar, count: 1, normalized: false)
        accessor.sparse = GLTFSparseStorage(values: values, valueOffset: 0, indices: indices,
                                            indexOffset: 0, indexComponentType: type, count: 1)
        #expect(throws: GLTFAccessorDataError.self) { try GLTFAccessorData.packed(accessor) }
    }

    @Test func accessorPackingAppliesSparseValuesToZeroBase() throws {
        let indices = GLTFBufferView(buffer: GLTFBuffer(data: Data([1])), length: 1, offset: 0, stride: 0)
        var valueBytes = Data(repeating: 0, count: 12)
        valueBytes.replaceSubrange(0..<4, with: [0, 0, 128, 63])
        let values = GLTFBufferView(buffer: GLTFBuffer(data: valueBytes), length: 12, offset: 0, stride: 0)
        let sparse = GLTFSparseStorage(values: values, valueOffset: 0, indices: indices,
                                       indexOffset: 0, indexComponentType: .unsignedByte, count: 1)
        let accessor = GLTFAccessor(bufferView: nil, offset: 0, componentType: .float,
                                    dimension: .scalar, count: 2, normalized: false)
        accessor.sparse = sparse
        #expect(try GLTFAccessorData.packed(accessor) == Data([0, 0, 0, 0, 0, 0, 128, 63]))
    }

    @Test func accessorPackingRejectsSparseValueViewStrideRange() throws {
        let indices = GLTFBufferView(buffer: GLTFBuffer(data: Data([0, 1])), length: 2, offset: 0, stride: 0)
        let values = GLTFBufferView(buffer: GLTFBuffer(data: Data(repeating: 0, count: 8)), length: 8, offset: 0, stride: 4)
        let sparse = GLTFSparseStorage(values: values, valueOffset: 0, indices: indices,
                                       indexOffset: 0, indexComponentType: .unsignedByte, count: 2)
        let accessor = GLTFAccessor(bufferView: nil, offset: 0, componentType: .float,
                                    dimension: .vector2, count: 2, normalized: false)
        accessor.sparse = sparse
        #expect(throws: GLTFAccessorDataError.self) { try GLTFAccessorData.packed(accessor) }
    }

    @Test func oversizedAccessorIsRejectedBeforeAllocation() async throws {
        let json: [String: Any] = [
            "asset": ["version": "2.0"],
            "buffers": [["byteLength": 12]],
            "bufferViews": [["buffer": 0, "byteOffset": 0, "byteLength": 12]],
            "accessors": [["bufferView": 0, "componentType": 5126, "count": 1_000_000_000, "type": "VEC3"]],
            "meshes": [["primitives": [["attributes": ["POSITION": 0]]]]],
            "nodes": [["mesh": 0]],
            "scenes": [["nodes": [0]]],
            "scene": 0,
        ]
        let url = try TestGLB.writeTemp(
            try TestGLB.serialize(json: json, bin: Data(repeating: 0, count: 12)),
            prefix: "oversized-accessor"
        )
        defer { try? FileManager.default.removeItem(at: url) }
        await #expect(throws: (any Error).self) {
            _ = try await MetalSceneLoader.load(url: url, device: device())
        }
    }

    @Test func accessorDimensionIsValidatedAtRendererBoundary() async throws {
        let json: [String: Any] = [
            "asset": ["version": "2.0"],
            "buffers": [["byteLength": 36]],
            "bufferViews": [["buffer": 0, "byteOffset": 0, "byteLength": 36]],
            "accessors": [["bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC4"]],
            "meshes": [["primitives": [["attributes": ["POSITION": 0]]]]],
            "nodes": [["mesh": 0]],
            "scenes": [["nodes": [0]]],
            "scene": 0,
        ]
        let url = try TestGLB.writeTemp(
            try TestGLB.serialize(json: json, bin: Data(repeating: 0, count: 36)),
            prefix: "wrong-accessor-dimension"
        )
        defer { try? FileManager.default.removeItem(at: url) }
        await #expect(throws: (any Error).self) {
            _ = try await MetalSceneLoader.load(url: url, device: device())
        }
    }

    @Test func authoredMorphWeightIsAppliedAtRest() async throws {
        let data = try Data(contentsOf:TestFixtures.morph)
        var json = try #require(JSONSerialization.jsonObject(with:data) as? [String:Any])
        var meshes = try #require(json["meshes"] as? [[String:Any]])
        meshes[0]["weights"] = [0.5]
        json["meshes"] = meshes
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("metal-morph-\(UUID())")
        try FileManager.default.copyItem(at: TestFixtures.morph.deletingLastPathComponent(), to: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent(TestFixtures.morph.lastPathComponent)
        try JSONSerialization.data(withJSONObject:json, options: .withoutEscapingSlashes).write(to:url)
        defer { try? FileManager.default.removeItem(at:url) }
        let scene = try await MetalSceneLoader.load(url:url,device:device())
        #expect(abs(scene.boundsMax.z - 0.5) < 0.0001)
    }

    @Test func generatedTangentsAreFiniteAndPerpendicular() async throws {
        let scene = try await MetalSceneLoader.load(url:TestFixtures.cube,device:device())
        for draw in scene.draws {
            let count = draw.vertexBuffer.length / MemoryLayout<MetalVertex>.stride
            let vertices = draw.vertexBuffer.contents().bindMemory(to:MetalVertex.self,capacity:count)
            for i in 0..<count {
                let n = vertices[i].normal
                let t = vertices[i].tangent
                #expect(t.x.isFinite && t.y.isFinite && t.z.isFinite)
                #expect(abs(n.x*t.x+n.y*t.y+n.z*t.z) < 0.001)
                #expect(abs(t.w) == 1)
            }
        }
    }

    @Test func packedVertexMatchesMSLLayout() {
        #expect(MemoryLayout<MetalVertex>.stride == 80)
        #expect(MemoryLayout<MetalVertex>.offset(of:\.normal) == 16)
        #expect(MemoryLayout<MetalVertex>.offset(of:\.tangent) == 32)
        #expect(MemoryLayout<MetalVertex>.offset(of:\.color) == 48)
        #expect(MemoryLayout<MetalVertex>.offset(of:\.uv0) == 64)
        #expect(MemoryLayout<MetalVertex>.offset(of:\.uv1) == 72)
    }

    private func camerasGLB(_ edit: (inout [String: Any]) -> Void) throws -> URL {
        var json = try GLBBox.peekDocumentJSON(from: TestFixtures.cameras)
        edit(&json)
        return try TestGLB.writeTempGLB(json: json, prefix: "metal-scene-loader")
    }

    @Test func cameraOnlySceneCanLoadWithoutMeshPrimitives() async throws {
        let url = try camerasGLB { json in
            json["scenes"] = [["nodes": [1, 2]]]
        }
        defer { try? FileManager.default.removeItem(at: url) }
        let scene = try await MetalSceneLoader.load(url: url, device: device())
        #expect(scene.draws.isEmpty)
        #expect(scene.boundsMin == .zero && scene.boundsMax == .zero)
        #expect(scene.asset.nodes.contains { $0.camera != nil })
    }

    @Test func cyclicParentGraphIsRejected() async throws {
        var json = try GLBBox.peekDocumentJSON(from: TestFixtures.cameras)
        var nodes = json["nodes"] as! [[String: Any]]
        nodes = [
            ["name": "A", "children": [1]],
            ["name": "B", "children": [0], "camera": 0],
        ]
        json["nodes"] = nodes
        json["scenes"] = [["nodes": [0]]]
        let url = try TestGLB.writeTempGLB(json: json, prefix: "cycle")
        defer { try? FileManager.default.removeItem(at: url) }
        await #expect(throws: (any Error).self) {
            _ = try await MetalSceneLoader.load(url: url, device: device())
        }
    }

    @Test func selfChildNodeIsRejected() async throws {
        var json = try GLBBox.peekDocumentJSON(from: TestFixtures.cameras)
        json["nodes"] = [["name": "Loop", "children": [0], "camera": 0]]
        json["scenes"] = [["nodes": [0]]]
        let url = try TestGLB.writeTempGLB(json: json, prefix: "self-cycle")
        defer { try? FileManager.default.removeItem(at: url) }
        await #expect(throws: (any Error).self) {
            _ = try await MetalSceneLoader.load(url: url, device: device())
        }
    }
}
