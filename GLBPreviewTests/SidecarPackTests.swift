import AppKit
import CoreGraphics
import Foundation
import RealityKit
import Testing
import simd
@testable import GLBPreview

struct SidecarPackTests {
    @Test func parseJSONStripsUTF8BOM() throws {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data("{\"asset\":{\"version\":\"2.0\"}}".utf8))
        let json = try GLBBox.parseJSON(data)
        #expect((json["asset"] as? [String: Any])?["version"] as? String == "2.0")
    }

    @Test func peekJSONRejectsSidecarJSON() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gltf-json-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("box.gltf")
        try Data("{\"asset\":{\"version\":\"2.0\"}}".utf8).write(to: url)
        #expect(throws: GLBBox.Error.invalidGLB) {
            try GLBBox.peekJSON(from: url)
        }
    }

    @Test func packsExternalBinIntoGLB() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gltf-pack-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let glb = try shortTriangleGLB()
        let parsed = try GLBBox.parse(glb)
        try parsed.bin.write(to: dir.appendingPathComponent("tri.bin"))
        var json = parsed.json
        var buffers = json["buffers"] as? [[String: Any]] ?? []
        buffers[0]["uri"] = "tri.bin"
        json["buffers"] = buffers
        let packed = try GLBBox.packSidecar(json) { uri in
            try Data(contentsOf: dir.appendingPathComponent(uri))
        }
        let packedBox = try GLBBox.parse(packed)
        #expect(packedBox.bin.count >= parsed.bin.count)
        let packedBuffers = packedBox.json["buffers"] as? [[String: Any]] ?? []
        #expect(packedBuffers.count == 1)
        #expect(packedBuffers.first?["uri"] == nil)
        let converted = try RealityPrepare.convert(packedBox)
        let prepared = try GLBBox.parse(converted)
        let accessors = prepared.json["accessors"] as? [[String: Any]] ?? []
        #expect(GLBBox.intValue(accessors.first?["componentType"]) == 5126)
    }

    @Test func packsDataURIBuffer() throws {
        let positions: [Float] = [0, 0, 0, 1, 0, 0, 0, 1, 0]
        var bin = Data()
        for value in positions {
            var bits = value.bitPattern.littleEndian
            Swift.withUnsafeBytes(of: &bits) { bin.append(contentsOf: $0) }
        }
        let json: [String: Any] = [
            "asset": ["version": "2.0"],
            "buffers": [[
                "byteLength": bin.count,
                "uri": "data:application/octet-stream;base64,\(bin.base64EncodedString())",
            ]],
            "bufferViews": [["buffer": 0, "byteOffset": 0, "byteLength": bin.count]],
            "accessors": [[
                "bufferView": 0,
                "componentType": 5126,
                "count": 3,
                "type": "VEC3",
            ]],
            "meshes": [["primitives": [["attributes": ["POSITION": 0]]]]],
            "nodes": [["mesh": 0]],
            "scenes": [["nodes": [0]]],
            "scene": 0,
        ]
        let packed = try GLBBox.packSidecar(json) { _ in
            Issue.record("data URI should not read a file")
            throw GLBBox.Error.missingBuffer
        }
        let box = try GLBBox.parse(packed)
        #expect(box.bin.count == bin.count)
    }

    /// Float-position sidecar with no prepare triggers should load the original `.gltf`
    /// (no temp pack). SHORT positions still pack+prepare so RealityKit can convert.
    @MainActor
    @Test func loadsPlainSidecarGLTFWithoutTempPack() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gltf-skip-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let positions: [Float] = [0, 0, 0, 1, 0, 0, 0, 1, 0]
        var bin = Data()
        for value in positions {
            var bits = value.bitPattern.littleEndian
            Swift.withUnsafeBytes(of: &bits) { bin.append(contentsOf: $0) }
        }
        try bin.write(to: dir.appendingPathComponent("tri.bin"))
        let json: [String: Any] = [
            "asset": ["version": "2.0"],
            "buffers": [["byteLength": bin.count, "uri": "tri.bin"]],
            "bufferViews": [["buffer": 0, "byteOffset": 0, "byteLength": bin.count]],
            "accessors": [[
                "bufferView": 0,
                "componentType": 5126,
                "count": 3,
                "type": "VEC3",
                "max": [1, 1, 0],
                "min": [0, 0, 0],
            ]],
            "meshes": [["primitives": [["attributes": ["POSITION": 0]]]]],
            "nodes": [["mesh": 0]],
            "scenes": [["nodes": [0]]],
            "scene": 0,
        ]
        let gltfURL = dir.appendingPathComponent("tri.gltf")
        try JSONSerialization.data(withJSONObject: json).write(to: gltfURL)

        #expect(!MetalRoughPrepare.needsConversion(json))
        #expect(!RealityPrepare.needsPrepare(json))

        let model = try await EntityLoader.load(from: gltfURL, includeAnimations: false)
        #expect(EntityLoader.modelComponentCount(in: model.entity) > 0)

        let thumb = try await EntityLoader.loadThumbnail(from: gltfURL)
        #expect(EntityLoader.modelComponentCount(in: thumb.entity) > 0)
    }

    @MainActor
    @Test func packsSidecarGLTFWhenRealityPrepareNeeded() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gltf-pack-load-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let glb = try shortTriangleGLB()
        let parsed = try GLBBox.parse(glb)
        try parsed.bin.write(to: dir.appendingPathComponent("tri.bin"))
        var json = parsed.json
        var buffers = json["buffers"] as? [[String: Any]] ?? []
        buffers[0]["uri"] = "tri.bin"
        json["buffers"] = buffers
        let gltfURL = dir.appendingPathComponent("tri.gltf")
        try JSONSerialization.data(withJSONObject: json).write(to: gltfURL)

        #expect(RealityPrepare.needsPrepare(json))
        let model = try await EntityLoader.load(from: gltfURL, includeAnimations: false)
        #expect(EntityLoader.modelComponentCount(in: model.entity) > 0)
    }

}
