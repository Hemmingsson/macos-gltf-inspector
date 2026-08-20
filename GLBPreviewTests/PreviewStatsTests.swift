import Foundation
import Testing
@testable import GLBPreview

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
        #expect(stats.pbrLabel == "Metalness")
        #expect(stats.morphGeometryCount == 0)
        #expect(!stats.isRigged)
        #expect(stats.overlayFacts.contains { $0.label == "materials" && $0.value == "1" })
        #expect(stats.overlayFacts.contains { $0.label == "textures" && $0.value == "1" })
    }

    @Test func trianglesAndFileSizeOverlay() {
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
        #expect(stats.vertexCount == 6)
        #expect(stats.overlayFacts.contains { $0.label == "triangles" && $0.value == "8" })
        #expect(stats.overlayFacts.contains { $0.label == "MB" && !$0.value.isEmpty })
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
        ]
        let stats = PreviewStats.from(json: json)
        #expect(stats.hasVertexColors)
        #expect(stats.isRigged)
        #expect(stats.morphGeometryCount == 1)
        #expect(stats.pbrLabel == "Specular")
        #expect(stats.textureCount == 2)
        #expect(stats.animationCount == 0)
        #expect(stats.overlayFacts.contains { $0.label == "Specular" })
        #expect(stats.overlayFacts.contains { $0.label == "vertex colors" })
        #expect(stats.overlayFacts.contains { $0.label == "rigged" })
        #expect(stats.overlayFacts.contains { $0.label == "morphs" && $0.value == "1" })
    }
}
