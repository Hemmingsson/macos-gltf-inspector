import AppKit
import CoreGraphics
import Foundation
import RealityKit
import Testing
import simd
@testable import GLBPreview

struct QAShotLaunchTests {
    @Test func parsesOutputAndFiles() throws {
        let parsed = try #require(QAShotLaunch.parse([
            "GLBPreview",
            "--qa-shots",
            "/tmp/qa-out",
            "--settle-ms",
            "1000",
            "/tmp/a.glb",
            "/tmp/b.gltf",
        ]))
        #expect(parsed.output.path == "/tmp/qa-out")
        #expect(parsed.files.map(\.lastPathComponent) == ["a.glb", "b.gltf"])
        #expect(parsed.settle == 1_000_000_000)
    }

    @Test func ignoresBareLaunch() {
        #expect(QAShotLaunch.parse(["GLBPreview"]) == nil)
    }

    @Test func titleBarDoesNotSaveEmptyCanvas() throws {
        let data = try #require(Self.png(width: 120, height: 80) { ctx in
            ctx.setFillColor(CGColor(srgbRed: 38 / 255, green: 38 / 255, blue: 38 / 255, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
            ctx.setFillColor(CGColor(srgbRed: 1, green: 0.3, blue: 0.3, alpha: 1))
            ctx.fill(CGRect(x: 4, y: 72, width: 8, height: 8))
        })
        #expect(QAShotLaunch.isEmptyCanvas(data))
    }

    @Test func paintedCenterIsNotEmptyCanvas() throws {
        let data = try #require(Self.png(width: 120, height: 80) { ctx in
            ctx.setFillColor(CGColor(srgbRed: 38 / 255, green: 38 / 255, blue: 38 / 255, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
            ctx.setFillColor(CGColor(srgbRed: 0.4, green: 0.35, blue: 0.3, alpha: 1))
            ctx.fill(CGRect(x: 30, y: 20, width: 60, height: 40))
        })
        #expect(!QAShotLaunch.isEmptyCanvas(data))
    }

    private static func png(width: Int, height: Int, draw: (CGContext) -> Void) -> Data? {
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        draw(ctx)
        guard let image = ctx.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .png, properties: [:])
    }
}

struct TextureAlphaUsageTests {
    @Test func constantZeroIsUnused() {
        #expect(GLBTextureAlpha.usage(minAlpha: 0, maxAlpha: 0) == .unused)
    }

    @Test func constantOneIsUnused() {
        #expect(GLBTextureAlpha.usage(minAlpha: 1, maxAlpha: 1) == .unused)
    }

    @Test func foliageSpanIsCutout() {
        #expect(GLBTextureAlpha.usage(minAlpha: 0, maxAlpha: 1) == .cutout)
    }
}

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

    @Test func unionDropsCmScaleLeftover() throws {
        var boxes: [BoundingBox] = (0..<8).map { i in
            let o = Float(i) * 0.2
            return BoundingBox(min: SIMD3(o, 0, 0), max: SIMD3(o + 1, 1, 1))
        }
        boxes.append(BoundingBox(min: SIMD3(-400, -700, -50), max: SIMD3(400, 700, 50)))
        let union = try #require(GLBPreviewCamera.unionModelBoxes(boxes))
        let extent = union.max - union.min
        #expect(extent.x < 4)
        #expect(extent.y < 2)
        #expect(extent.z < 2)
    }

    @MainActor
    @Test func turntableCentersOffsetSketchfabRoot() {
        let root = Entity()
        root.position = SIMD3(409, -17, -36)
        let model = ModelEntity(mesh: .generateBox(size: 2), materials: [SimpleMaterial()])
        root.addChild(model)
        let assembled = GLBPreviewCamera.makeTurntable(for: root)
        let bounds = GLBPreviewCamera.modelBounds(of: assembled.pivot, relativeTo: assembled.pivot)
        #expect(abs(bounds.center.x) < 0.15)
        #expect(abs(bounds.center.y) < 0.15)
        #expect(abs(bounds.center.z) < 0.15)
        let extent = bounds.max - bounds.min
        #expect(extent.x > 1.5 && extent.x < 2.5)
    }

    @Test func unionKeepsEqualSizedTiles() throws {
        let boxes = (0..<6).map { i in
            let o = Float(i) * 200
            return BoundingBox(min: SIMD3(o, 0, 0), max: SIMD3(o + 180, 10, 180))
        }
        let union = try #require(GLBPreviewCamera.unionModelBoxes(boxes))
        let extent = union.max - union.min
        #expect(extent.x > 1000)
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

struct PipelineHoleTests {
    /// `convert(primitive:)` returns nil for anything except TRIANGLES and POINTS.
    @MainActor
    @Test func linesOnlyAssetHasNoVisibleMesh() async throws {
        let url = try GLBBox.writePrepared(try primitiveModeGLB(mode: 1), prefix: "lines-only")
        defer { try? FileManager.default.removeItem(at: url) }
        await #expect(throws: Error.self) {
            _ = try await GLBEntityLoader.load(from: url, includeAnimations: false)
        }
    }

    @MainActor
    @Test func triangleStripOnlyAssetHasNoVisibleMesh() async throws {
        let url = try GLBBox.writePrepared(try primitiveModeGLB(mode: 5), prefix: "tristrip-only")
        defer { try? FileManager.default.removeItem(at: url) }
        await #expect(throws: Error.self) {
            _ = try await GLBEntityLoader.load(from: url, includeAnimations: false)
        }
    }

    @MainActor
    @Test func trianglesOnlyAssetLoads() async throws {
        let url = try GLBBox.writePrepared(try primitiveModeGLB(mode: 4), prefix: "tris-only")
        defer { try? FileManager.default.removeItem(at: url) }
        let model = try await GLBEntityLoader.load(from: url, includeAnimations: false)
        #expect(GLBEntityLoader.modelComponentCount(in: model.entity) > 0)
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

    /// End-to-end proof of the fused load pipeline: single header parse → convert →
    /// `LoadedModel` with stats, against a real `.glb`.
    @MainActor
    @Test func loadsRealGLBEndToEnd() async throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repoRoot.appendingPathComponent("scripts/tiny.glb")
        try #require(FileManager.default.fileExists(atPath: url.path))
        let model = try await GLBEntityLoader.load(from: url, includeAnimations: false)
        #expect(GLBEntityLoader.modelComponentCount(in: model.entity) > 0)
        #expect(model.stats.meshCount >= 1)
    }
}

/// Three vertices. Mode 4 = TRIANGLES (legal). Mode 1 = LINES, 5 = TRIANGLE_STRIP.
private func primitiveModeGLB(mode: Int) throws -> Data {
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
            "min": [0, 0, 0],
            "max": [1, 1, 0],
        ]],
        "meshes": [["primitives": [[
            "attributes": ["POSITION": 0],
            "mode": mode,
        ]]]],
        "nodes": [["mesh": 0]],
        "scenes": [["nodes": [0]]],
        "scene": 0,
    ]
    return try GLBBox.serialize(json: json, bin: bin)
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
        #expect(stats.opaqueMaterialCount == 1)
        #expect(stats.transparentMaterialCount == 0)
        #expect(stats.animationCount == 0)
        #expect(stats.nodeCount == 3)
        #expect(stats.textureCount == 1)
        #expect(stats.durationSeconds == nil)
        #expect(stats.previewRows.contains { $0.label == "Materials" && $0.value == "1" })
        #expect(stats.previewRows.contains { $0.label == "Textures" && $0.value == "1" })
        #expect(!stats.previewRows.contains { $0.label == "PBR" })
        #expect(!stats.previewRows.contains { $0.label == "Animations" })
        #expect(!stats.previewRows.contains { $0.label == "Morph geometries" })
        #expect(!stats.previewRows.contains { $0.label == "Rigged geometries" })
    }

    @Test func trianglesAndTransparentFromPrimitives() {
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
            "materials": [
                [:],
                ["alphaMode": "MASK"],
                ["alphaMode": "BLEND"],
                [
                    "alphaMode": "OPAQUE",
                    "extensions": ["KHR_materials_transmission": ["transmissionFactor": 1]],
                ],
            ],
        ]
        let stats = GLBPreviewStats.from(json: json, fileSizeBytes: 1_500_000)
        #expect(stats.triangleCount == 8)
        #expect(stats.vertexCount == 6)
        #expect(stats.opaqueMaterialCount == 2)
        #expect(stats.transparentMaterialCount == 2)
        #expect(stats.previewRows.contains { $0.label == "Geometry" && $0.value == "Triangles 8" })
        #expect(stats.previewRows.contains { $0.label == "Size" && ($0.value.contains("MB") || $0.value.contains("KB")) })
    }

    @Test func sketchfabStyleFlagsFromJSON() {
        let json: [String: Any] = [
            "accessors": [
                ["count": 3],
            ],
            "meshes": [[
                "primitives": [[
                    "attributes": [
                        "POSITION": 0,
                        "TEXCOORD_0": 0,
                        "COLOR_0": 0,
                        "JOINTS_0": 0,
                    ],
                    "targets": [["POSITION": 0]],
                ]],
            ]],
            "materials": [[
                "extensions": ["KHR_materials_pbrSpecularGlossiness": [:]],
            ]],
            "textures": [[:], [:]],
            "skins": [["joints": [0]]],
            "nodes": [["scale": [2, 1, 1]]],
        ]
        let stats = GLBPreviewStats.from(json: json)
        #expect(stats.hasUVLayers)
        #expect(stats.hasVertexColors)
        #expect(stats.isRigged)
        #expect(stats.morphGeometryCount == 1)
        #expect(stats.hasScaleTransforms)
        #expect(stats.pbrLabel == "Specular")
        #expect(stats.textureCount == 2)
        #expect(!stats.previewRows.contains { $0.label == "UV Layers" })
        #expect(stats.previewRows.contains { $0.label == "PBR" && $0.value == "Specular" })
        #expect(stats.previewRows.contains { $0.label == "Vertex colors" && $0.value == "Yes" })
        #expect(stats.previewRows.contains { $0.label == "Rigged geometries" && $0.value == "Yes" })
        #expect(stats.previewRows.contains { $0.label == "Morph geometries" && $0.value == "1" })
        #expect(stats.previewRows.contains { $0.label == "Scale transformations" && $0.value == "Yes" })
        #expect(!stats.previewRows.contains { $0.label == "Animations" })
    }

    @Test func omitsDurationWithoutAccessorMax() {
        let json: [String: Any] = [
            "animations": [["samplers": [["input": 0]]]],
            "accessors": [["count": 10]],
        ]
        #expect(GLBPreviewStats.from(json: json).durationSeconds == nil)
    }
}

struct TextureChannelExtractTests {
    /// macOS PNG decode is typically BGRA. glTF metal lives in B; RealityKit reads R.
    @Test func extractsBlueFromBGRA() throws {
        let image = try #require(Self.bgraImage(red: 255, green: 128, blue: 0))
        let context = GLBRealityKitResourceContext()
        let extracted = try #require(context.singleChannelImage(from: image, channels: .blue))
        #expect(Self.grayPixel(extracted) == 0)
    }

    @Test func extractsGreenFromBGRA() throws {
        let image = try #require(Self.bgraImage(red: 255, green: 128, blue: 0))
        let context = GLBRealityKitResourceContext()
        let extracted = try #require(context.singleChannelImage(from: image, channels: .green))
        #expect(Self.grayPixel(extracted) == 128)
    }

    private static func bgraImage(red: UInt8, green: UInt8, blue: UInt8) -> CGImage? {
        var pixel: [UInt8] = [blue, green, red, 255]
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let ctx = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: space,
            bitmapInfo: info
        ) else { return nil }
        return ctx.makeImage()
    }

    private static func grayPixel(_ image: CGImage) -> UInt8 {
        let data = image.dataProvider!.data!
        return CFDataGetBytePtr(data)[0]
    }
}
