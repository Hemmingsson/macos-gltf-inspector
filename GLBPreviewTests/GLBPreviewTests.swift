import Foundation
import RealityKit
import Testing
import simd
@testable import GLBPreview

struct ThinAxisTests {
    @Test func doorLikeThinX() {
        #expect(GLBPreviewCamera.thinAxis(SIMD3(0.05, 2.0, 0.8)) == 0)
    }

    @Test func doorLikeThinZ() {
        #expect(GLBPreviewCamera.thinAxis(SIMD3(0.8, 2.0, 0.05)) == 2)
    }

    @Test func snowdropKeepsThreeQuarter() {
        #expect(GLBPreviewCamera.thinAxis(SIMD3(1.83, 0.11, 0.47)) == nil)
    }

    @Test func cubeIsNotThin() {
        #expect(GLBPreviewCamera.thinAxis(SIMD3(1, 1, 1)) == nil)
    }
}

struct ModelBoundsTests {
    @MainActor
    @Test func ignoresHelperWithoutMesh() async throws {
        let root = Entity()
        let model = ModelEntity(mesh: .generateBox(size: 1), materials: [SimpleMaterial()])
        model.position = .zero
        root.addChild(model)

        let helper = Entity()
        helper.position = SIMD3(100, 100, 100)
        helper.scale = SIMD3(50, 50, 50)
        root.addChild(helper)

        let bounds = GLBPreviewCamera.modelBounds(of: root)
        let extent = bounds.max - bounds.min
        #expect(extent.x < 2)
        #expect(extent.y < 2)
        #expect(extent.z < 2)
    }
}

struct RealityPrepareTests {
    @Test func needsPrepareQuantization() {
        let json: [String: Any] = [
            "extensionsUsed": ["KHR_mesh_quantization"],
        ]
        #expect(GLBRealityPrepare.needsPrepare(json))
    }

    @Test func needsPrepareInstancing() {
        let json: [String: Any] = [
            "extensionsUsed": ["EXT_mesh_gpu_instancing"],
        ]
        #expect(GLBRealityPrepare.needsPrepare(json))
    }

    @Test func needsPrepareWebP() {
        let json: [String: Any] = [
            "extensionsUsed": ["EXT_texture_webp"],
        ]
        #expect(GLBRealityPrepare.needsPrepare(json))
    }

    @Test func skipsPlainMesh() {
        let json: [String: Any] = [
            "asset": ["version": "2.0"],
            "accessors": [
                ["componentType": 5126, "count": 3, "type": "VEC3"],
            ],
        ]
        #expect(!GLBRealityPrepare.needsPrepare(json))
    }

    @Test func dequantizesShortPositions() throws {
        let glb = try GLBBox.parse(try shortTriangleGLB())
        let converted = try GLBRealityPrepare.convert(glb)
        let prepared = try GLBBox.parse(converted)
        let accessors = prepared.json["accessors"] as? [[String: Any]] ?? []
        let position = accessors.first { ($0["type"] as? String) == "VEC3" }
        #expect(GLBBox.intValue(position?["componentType"]) == 5126)
    }

    @Test func dequantizesShortPositionsToRawValues() throws {
        let glb = try GLBBox.parse(try shortTriangleGLB())
        let converted = try GLBRealityPrepare.convert(glb)
        let prepared = try GLBBox.parse(converted)
        let accessors = prepared.json["accessors"] as? [[String: Any]] ?? []
        let bufferViews = prepared.json["bufferViews"] as? [[String: Any]] ?? []
        let position = try #require(accessors.first { ($0["type"] as? String) == "VEC3" })
        #expect(GLBBox.intValue(position["componentType"]) == 5126)
        let viewIndex = try #require(GLBBox.intValue(position["bufferView"]))
        let offset = GLBBox.intValue(bufferViews[viewIndex]["byteOffset"]) ?? 0
        let count = GLBBox.intValue(position["count"]) ?? 0
        let floats = (0..<(count * 3)).map { i in
            Float(bitPattern: GLBBox.readUInt32(prepared.bin, offset + i * 4))
        }
        // The node carries no transform, so non-normalized quantized positions
        // must dequantize to their raw integer values, not a min/max remap.
        #expect(floats == [0, 0, 0, 100, 0, 0, 0, 100, 0])
    }

    @Test func skipAccessorIndicesIncludesMeshoptViews() {
        let json: [String: Any] = [
            "bufferViews": [
                ["byteLength": 12],
                ["byteLength": 12, "extensions": ["EXT_meshopt_compression": ["count": 3]]],
            ],
            "accessors": [
                ["bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3"],
                ["bufferView": 1, "componentType": 5122, "count": 3, "type": "VEC3"],
            ],
        ]
        let skip = GLBRealityPrepare.skipAccessorIndices(json)
        #expect(!skip.contains(0))
        #expect(skip.contains(1))
    }

    @Test func expandsTwoGPUInstances() throws {
        let glb = try GLBBox.parse(try instancedGLB(count: 2))
        let converted = try GLBRealityPrepare.convert(glb)
        let prepared = try GLBBox.parse(converted)
        let nodes = prepared.json["nodes"] as? [[String: Any]] ?? []
        let meshed = nodes.filter { $0["mesh"] != nil }
        #expect(meshed.count == 2)
        #expect(nodes.count >= 3)
    }

    @Test func namesUnnamedJointsBySkinIndex() {
        var json: [String: Any] = [
            "nodes": [
                ["name": ""],
                ["name": "hip"],
                [:],
            ],
            "skins": [
                ["joints": [0, 1]],
                ["joints": [2]],
            ],
        ]
        #expect(GLBRealityPrepare.hasUnnamedSkinJoints(json))
        GLBRealityPrepare.nameUnnamedSkinJoints(&json)
        let nodes = json["nodes"] as? [[String: Any]] ?? []
        #expect(nodes[0]["name"] as? String == "joint-0")
        #expect(nodes[1]["name"] as? String == "hip")
        #expect(nodes[2]["name"] as? String == "joint-0")
        #expect(!GLBRealityPrepare.hasUnnamedSkinJoints(json))
        #expect(GLBSkin.resolvedName(nil, index: 4) == "joint-4")
        #expect(GLBSkin.resolvedName("Root", index: 4) == "Root")
    }
}

struct SpecGlossTests {
    @Test func needsConversionWhenExtensionPresent() {
        let json: [String: Any] = [
            "materials": [
                ["extensions": ["KHR_materials_pbrSpecularGlossiness": ["glossinessFactor": 1]]],
            ],
        ]
        #expect(GLBMetalRoughPrepare.needsConversion(json))
    }

    @Test func skipsMetalRoughOnly() {
        let json: [String: Any] = [
            "materials": [
                ["pbrMetallicRoughness": ["metallicFactor": 0]],
            ],
        ]
        #expect(!GLBMetalRoughPrepare.needsConversion(json))
    }

    @Test func skipsBakeWhenTooManyImages() {
        let images = Array(repeating: ["mimeType": "image/png"], count: 41)
        let materials: [[String: Any]] = [
            ["extensions": ["KHR_materials_pbrSpecularGlossiness": ["specularGlossinessTexture": ["index": 0]]]],
        ]
        #expect(!GLBMetalRoughPrepare.shouldBakeTextures(json: ["images": images], materials: materials))
    }

    @Test func downsamplesLongestEdge() {
        let source = PixelImage(width: 2048, height: 1024, bytes: [UInt8](repeating: 255, count: 2048 * 1024 * 4))
        let scaled = source.downsampled(maxEdge: 1024)
        #expect(scaled.width == 1024)
        #expect(scaled.height == 512)
    }
}

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
        let converted = try GLBRealityPrepare.convert(packedBox)
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

}

struct LoaderHelpersTests {
    @MainActor
    @Test func modelComponentCountWalksTree() {
        let root = Entity()
        #expect(GLBEntityLoader.modelComponentCount(in: root) == 0)
        root.addChild(ModelEntity(mesh: .generateBox(size: 0.2), materials: [SimpleMaterial()]))
        #expect(GLBEntityLoader.modelComponentCount(in: root) == 1)
    }
}

private func shortTriangleGLB() throws -> Data {
    var bin = Data()
    // 3 SHORT VEC3 positions: (0,0,0) (100,0,0) (0,100,0)
    for value in [Int16(0), 0, 0, Int16(100), 0, 0, Int16(0), 100, 0] {
        var bits = value.littleEndian
        Swift.withUnsafeBytes(of: &bits) { bin.append(contentsOf: $0) }
    }
    let json: [String: Any] = [
        "asset": ["version": "2.0"],
        "buffers": [["byteLength": bin.count]],
        "bufferViews": [[
            "buffer": 0,
            "byteOffset": 0,
            "byteLength": bin.count,
        ]],
        "accessors": [[
            "bufferView": 0,
            "componentType": 5122,
            "count": 3,
            "type": "VEC3",
            "max": [100, 100, 0],
            "min": [0, 0, 0],
        ]],
        "meshes": [[
            "primitives": [[
                "attributes": ["POSITION": 0],
            ]],
        ]],
        "nodes": [["mesh": 0]],
        "scenes": [["nodes": [0]]],
        "scene": 0,
    ]
    return try GLBBox.serialize(json: json, bin: bin)
}

private func instancedGLB(count: Int) throws -> Data {
    var bin = Data()
    for value: Float in [0, 0, 0, 1, 0, 0, 0, 1, 0] {
        var bits = value.bitPattern.littleEndian
        Swift.withUnsafeBytes(of: &bits) { bin.append(contentsOf: $0) }
    }
    let positionLength = bin.count
    // TRANSLATION instances along X
    for i in 0..<count {
        for value: Float in [Float(i), 0, 0] {
            var bits = value.bitPattern.littleEndian
            Swift.withUnsafeBytes(of: &bits) { bin.append(contentsOf: $0) }
        }
    }
    let json: [String: Any] = [
        "asset": ["version": "2.0"],
        "extensionsUsed": ["EXT_mesh_gpu_instancing"],
        "buffers": [["byteLength": bin.count]],
        "bufferViews": [
            ["buffer": 0, "byteOffset": 0, "byteLength": positionLength],
            ["buffer": 0, "byteOffset": positionLength, "byteLength": count * 12],
        ],
        "accessors": [
            ["bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3"],
            ["bufferView": 1, "componentType": 5126, "count": count, "type": "VEC3"],
        ],
        "meshes": [["primitives": [["attributes": ["POSITION": 0]]]]],
        "nodes": [[
            "mesh": 0,
            "extensions": [
                "EXT_mesh_gpu_instancing": [
                    "attributes": ["TRANSLATION": 1],
                ],
            ],
        ]],
        "scenes": [["nodes": [0]]],
        "scene": 0,
    ]
    return try GLBBox.serialize(json: json, bin: bin)
}

struct PreviewStatsTests {
    @Test func countsAndDurationFromJSON() {
        let json: [String: Any] = [
            "meshes": [[:], [:]],
            "materials": [[:]],
            "animations": [[
                "samplers": [["input": 0]],
            ]],
            "nodes": [[:], [:], [:]],
            "textures": [[:]],
            "accessors": [
                ["max": [2.5]],
            ],
        ]
        let stats = GLBPreviewStats.from(json: json)
        #expect(stats.meshCount == 2)
        #expect(stats.materialCount == 1)
        #expect(stats.animationCount == 1)
        #expect(stats.nodeCount == 3)
        #expect(stats.textureCount == 1)
        #expect(stats.durationSeconds == 2.5)
        #expect(stats.previewLines.contains("Meshes 2"))
    }

    @Test func omitsDurationWithoutAccessorMax() {
        let json: [String: Any] = [
            "animations": [["samplers": [["input": 0]]]],
            "accessors": [["count": 10]],
        ]
        #expect(GLBPreviewStats.from(json: json).durationSeconds == nil)
    }
}
