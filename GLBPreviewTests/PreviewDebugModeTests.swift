import Foundation
import RealityKit
import Testing
@testable import GLBPreview

struct PreviewDebugModeTests {
    @Test func titlesAndVariableValue() {
        #expect(PreviewDebugMode.none.shortTitle == "None")
        #expect(PreviewDebugMode.wire.shortTitle == "Wire")
        #expect(PreviewDebugMode.visualization(.normal).shortTitle == "Nrm")
        #expect(PreviewDebugMode.visualization(.textureCoordinates).shortTitle == "UV")
        #expect(PreviewDebugMode.variableValue(index: 0, count: 1) == 0)
        #expect(PreviewDebugMode.variableValue(index: 0, count: 4) == 0)
        #expect(PreviewDebugMode.variableValue(index: 1, count: 4) == 1)
        #expect(PreviewDebugMode.variableValue(index: 2, count: 4) == 0.5)
        #expect(PreviewDebugMode.variableValue(index: 3, count: 4) == 0)
    }

    @Test func baseAndUVMeshIncludesExpectedModes() {
        let json: [String: Any] = [
            "accessors": [["count": 3]],
            "meshes": [[
                "primitives": [[
                    "attributes": [
                        "POSITION": 0,
                        "TEXCOORD_0": 0,
                    ],
                    "indices": 0,
                ]],
            ]],
            "materials": [[
                "pbrMetallicRoughness": ["baseColorFactor": [1, 1, 1, 1]],
            ]],
        ]
        let modes = PreviewDebugMode.available(from: json)
        #expect(modes.map(\.shortTitle) == ["None", "Wire", "UV", "Base"])
        #expect(!modes.contains { $0.shortTitle == "Diff" || $0.shortTitle == "RGB" })
    }

    @Test func occlusionAddsAO() {
        let json: [String: Any] = [
            "meshes": [[
                "primitives": [[
                    "attributes": ["POSITION": 0, "NORMAL": 0],
                    "mode": 4,
                ]],
            ]],
            "materials": [[
                "occlusionTexture": ["index": 0],
            ]],
        ]
        let titles = PreviewDebugMode.available(from: json).map(\.shortTitle)
        #expect(titles.contains("AO"))
        #expect(titles.contains("Nrm"))
        #expect(titles.contains("Wire"))
        #expect(!titles.contains("LSpec"))
    }

    @Test func unlitSkipsMetallicRoughness() {
        let json: [String: Any] = [
            "meshes": [[
                "primitives": [[
                    "attributes": ["POSITION": 0],
                    "mode": 4,
                ]],
            ]],
            "materials": [[
                "extensions": ["KHR_materials_unlit": [:]],
                "pbrMetallicRoughness": [
                    "metallicFactor": 0,
                    "roughnessFactor": 0.2,
                ],
            ]],
        ]
        let titles = PreviewDebugMode.available(from: json).map(\.shortTitle)
        #expect(titles == ["None", "Wire", "Base"])
    }

    @Test func metalRoughTextureAddsMetAndRgh() {
        let json: [String: Any] = [
            "materials": [[
                "pbrMetallicRoughness": [
                    "metallicRoughnessTexture": ["index": 0],
                ],
            ]],
        ]
        let titles = PreviewDebugMode.available(from: json).map(\.shortTitle)
        #expect(titles.contains("Met"))
        #expect(titles.contains("Rgh"))
        #expect(titles.contains("Base"))
        #expect(!titles.contains("Wire"))
    }

    @Test func wrapUsesFilteredCount() {
        let modes = PreviewDebugMode.available(from: [
            "materials": [[:]],
        ])
        #expect(modes.first == Optional(PreviewDebugMode.none))
        let next = (0 + 1) % modes.count
        #expect(modes[next].shortTitle == "Base")
    }
}
