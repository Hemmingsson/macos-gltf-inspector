import AppKit
import CoreGraphics
import Foundation
import RealityKit
import Testing
import simd
@testable import GLBPreview

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
        let stats = PreviewStats.from(json: json)
        #expect(stats.materialCount == 1)
        #expect(stats.animationCount == 0)
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
        let stats = PreviewStats.from(json: json, fileSizeBytes: 1_500_000)
        #expect(stats.triangleCount == 8)
        #expect(stats.vertexCount == 6)
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
        let stats = PreviewStats.from(json: json)
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
        #expect(PreviewStats.from(json: json).durationSeconds == nil)
    }
}
