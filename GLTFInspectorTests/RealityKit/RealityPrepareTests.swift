import AppKit
import CoreGraphics
import Foundation
@testable import GLTFCore
import RealityKit
@testable import RendererRealityKit
import simd
import Testing

struct RealityPrepareTests {
    /// Quantized accessors are converted at convert time (`QuantizedMeshTests`), not rewritten.
    @Test func quantizationNeedsNoPrepare() {
        let json: [String: Any] = [
            "extensionsUsed": ["KHR_mesh_quantization"],
            "accessors": [["componentType": 5122, "count": 3, "type": "VEC3"]],
        ]
        #expect(!RealityPrepare.needsPrepare(json))
    }

    @Test func needsPrepareInstancing() {
        let json: [String: Any] = [
            "extensionsUsed": ["EXT_mesh_gpu_instancing"],
        ]
        #expect(RealityPrepare.needsPrepare(json))
    }

    /// GLTFKit2 decodes WebP itself (`PrepareFreeInputsTests`), so WebP alone needs no rewrite.
    @Test func webpNeedsNoPrepare() {
        let json: [String: Any] = [
            "extensionsUsed": ["EXT_texture_webp"],
        ]
        #expect(!RealityPrepare.needsPrepare(json))
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

    @Test func expandsTwoGPUInstances() throws {
        let glb = try GLBBox.parse(try instancedGLB(count: 2))
        let converted = try RealityPrepare.convert(glb)
        let prepared = try GLBBox.parse(converted)
        let nodes = prepared.json["nodes"] as? [[String: Any]] ?? []
        let meshed = nodes.filter { $0["mesh"] != nil }
        #expect(meshed.count == 2)
        #expect(nodes.count >= 3)
    }

    @Test func resolvesUnnamedJointsBySkinIndex() {
        #expect(Skin.resolvedName(nil, index: 4) == "joint-4")
        #expect(Skin.resolvedName("Root", index: 4) == "Root")
    }
}
