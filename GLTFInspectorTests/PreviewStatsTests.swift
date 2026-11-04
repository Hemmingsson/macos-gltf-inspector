import Foundation
@testable import GLTFCore
import Testing

struct PreviewStatsTests {
    @Test func countsMaterialsAndTexturesFromJSON() {
        let json: [String: Any] = [
            "meshes": [[:], [:]],
            "materials": [[:]],
            "textures": [[:]],
        ]
        let stats = PreviewStats.from(json: json)
        #expect(stats.materialCount == 1)
        #expect(stats.animationCount == 0)
        #expect(stats.textureCount == 1)
        #expect(stats.maxTextureEdge == nil)
    }

    @Test func animationCountIsTheCallers() {
        let stats = PreviewStats.from(
            json: ["materials": [[:]]],
            animationCount: 2
        )
        #expect(stats.animationCount == 2)
    }

    @Test func maxTextureEdgeFromEmbeddedPNG() throws {
        let png = tinyPNG()
        var bin = Data()
        bin.append(png)
        let json: [String: Any] = [
            "asset": ["version": "2.0"],
            "buffers": [["byteLength": bin.count]],
            "bufferViews": [["buffer": 0, "byteOffset": 0, "byteLength": png.count]],
            "images": [["mimeType": "image/png", "bufferView": 0]],
            "textures": [["source": 0]],
            "materials": [[:]],
            "meshes": [[:]],
            "nodes": [[:]],
            "scenes": [["nodes": [0]]],
            "scene": 0,
        ]
        let data = try TestGLB.serialize(json: json, bin: bin)
        let url = try TestGLB.writeTemp(data, prefix: "stats-tex")
        defer { try? FileManager.default.removeItem(at: url) }

        let stats = PreviewStats.from(json: json, resourceURL: url)
        #expect(stats.textureCount == 1)
        #expect(stats.maxTextureEdge == 1)
    }

    @Test func maxTextureEdgeFromSidecarBufferView() throws {
        let png = tinyPNG()
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("stats-sidecar-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try png.write(to: folder.appendingPathComponent("image data.bin"))
        let json: [String: Any] = [
            "buffers": [["uri": "image%20data.bin", "byteLength": png.count]],
            "bufferViews": [["buffer": 0, "byteOffset": 0, "byteLength": png.count]],
            "images": [["mimeType": "image/png", "bufferView": 0]],
            "textures": [["source": 0]],
        ]
        let stats = PreviewStats.from(json: json, resourceURL: folder.appendingPathComponent("model.gltf"))
        #expect(stats.maxTextureEdge == 1)
    }

    @Test func trianglesAndFileSize() {
        let json: [String: Any] = [
            "accessors": [
                ["count": 9],
                ["count": 6],
                ["count": 5],
            ],
            "meshes": [
                ["primitives": [
                    ["indices": 0],
                    ["attributes": ["POSITION": 1], "mode": 4],
                    ["indices": 2, "mode": 5],
                    ["indices": 2, "mode": 1],
                ]],
            ],
            "materials": [[:]],
        ]
        let stats = PreviewStats.from(json: json, fileSizeBytes: 1_500_000)
        #expect(stats.triangleCount == 8)
        #expect(stats.fileSizeBytes == 1_500_000)
    }
}
