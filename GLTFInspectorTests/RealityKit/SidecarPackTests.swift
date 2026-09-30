import AppKit
import CoreGraphics
import Foundation
@testable import GLTFCore
import RealityKit
@testable import RendererRealityKit
import simd
import Testing

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

    @MainActor
    @Test func loadsPlainSidecarGLTF() async throws {
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


        let model = try await EntityLoader.load(from: gltfURL, includeAnimations: false)
        #expect(EntityLoader.modelComponentCount(in: model.entity) > 0)

        let thumb = try await EntityLoader.loadThumbnail(from: gltfURL)
        #expect(EntityLoader.modelComponentCount(in: thumb.entity) > 0)
    }

    @MainActor
    @Test func quantizedSidecarGLTFLoads() async throws {
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

        let model = try await EntityLoader.load(from: gltfURL, includeAnimations: false)
        #expect(EntityLoader.modelComponentCount(in: model.entity) > 0)
    }


    /// GLTFKit2 resolves sidecars itself now; `EntityLoader` still refuses URIs that leave the
    /// file's folder before it hands the file over.
    @MainActor
    @Test func rejectsSidecarURIOutsideTheFolder() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gltf-escape-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let json: [String: Any] = [
            "asset": ["version": "2.0"],
            "buffers": [["byteLength": 36, "uri": "../secret.bin"]],
        ]
        let url = dir.appendingPathComponent("escape.gltf")
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        await #expect(throws: (any Error).self) {
            _ = try await EntityLoader.load(from: url, includeAnimations: false)
        }
    }
}
