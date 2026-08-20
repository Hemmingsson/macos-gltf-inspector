import AppKit
import CoreGraphics
import Foundation
import RealityKit
import Testing
import simd
@testable import GLBPreview

struct RealityPrepareTests {
    @Test func needsPrepareQuantization() {
        let json: [String: Any] = [
            "extensionsUsed": ["KHR_mesh_quantization"],
        ]
        #expect(RealityPrepare.needsPrepare(json))
    }

    @Test func needsPrepareInstancing() {
        let json: [String: Any] = [
            "extensionsUsed": ["EXT_mesh_gpu_instancing"],
        ]
        #expect(RealityPrepare.needsPrepare(json))
    }

    @Test func needsPrepareWebP() {
        let json: [String: Any] = [
            "extensionsUsed": ["EXT_texture_webp"],
        ]
        #expect(RealityPrepare.needsPrepare(json))
    }

    @Test func skipsPlainMesh() {
        let json: [String: Any] = [
            "asset": ["version": "2.0"],
            "accessors": [
                ["componentType": 5126, "count": 3, "type": "VEC3"],
            ],
        ]
        #expect(!RealityPrepare.needsPrepare(json))
    }

    @Test func dequantizesShortPositionsToRawValues() throws {
        let glb = try GLBBox.parse(try shortTriangleGLB())
        let converted = try RealityPrepare.convert(glb)
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
        let skip = RealityPrepare.skipAccessorIndices(json)
        #expect(!skip.contains(0))
        #expect(skip.contains(1))
    }

    @Test func expandsTwoGPUInstances() throws {
        let glb = try GLBBox.parse(try instancedGLB(count: 2))
        let converted = try RealityPrepare.convert(glb)
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
        #expect(RealityPrepare.hasUnnamedSkinJoints(json))
        RealityPrepare.nameUnnamedSkinJoints(&json)
        let nodes = json["nodes"] as? [[String: Any]] ?? []
        #expect(nodes[0]["name"] as? String == "joint-0")
        #expect(nodes[1]["name"] as? String == "hip")
        #expect(nodes[2]["name"] as? String == "joint-0")
        #expect(!RealityPrepare.hasUnnamedSkinJoints(json))
        #expect(Skin.resolvedName(nil, index: 4) == "joint-4")
        #expect(Skin.resolvedName("Root", index: 4) == "Root")
    }
}
