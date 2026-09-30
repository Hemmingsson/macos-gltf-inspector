import Foundation
@testable import GLTFCore
import RealityKit
@testable import RendererRealityKit
import Testing

/// The sidebar document describes the *file*, not the subset that survived RealityKit convert.
/// These tests pin the difference. Parsing without a renderer: `SceneModelFromJSONTests.swift`.
struct SceneModelFromJSONConvertTests {
    @MainActor
    @Test func ignoredExtensionStillListsWholeFile() async throws {
        let loaded = try await loadModel(try ignoredExtensionGLB(), includeAnimations: true)

        // The renderer says it dropped the extension…
        #expect(loaded.convertProblems.items.contains {
            $0.code == .ignoredExtension && $0.message.contains("KHR_materials_volume")
        })

        // …and the sidebar still describes everything the file declares.
        #expect(loaded.document.nodes.map(\.name) == ["Root", "Body", "Trim"])
        #expect(loaded.document.nodes[0].children == [1, 2])
        #expect(loaded.document.materials.map(\.name) == ["Glass", "Paint"])
        #expect(loaded.document.animations.map(\.name) == ["Spin"])
        #expect(loaded.document.scenes.map(\.rootNodeIndices) == [[0]])
    }

    @MainActor
    @Test func specGlossWorkflowSurvivesTheMetalRoughRewrite() async throws {
        // Prepare rewrites spec/gloss into metal/rough before convert; the document is built
        // from the untouched file, so the inspector reports the workflow that was authored.
        let loaded = try await loadModel(try specGlossGLB())
        let material = try #require(loaded.document.materials.first)
        #expect(material.workflow == .specularGlossiness)
        #expect(material.metallicFactor == nil)
        #expect(material.roughnessFactor == nil)
        // The rewrite really did happen — convert produced a metal/rough RealityKit material.
        #expect(!pbrMaterials(in: loaded.entity).isEmpty)
    }

    @MainActor
    @Test func gpuInstancingKeepsTheAuthoredNodeCount() async throws {
        // Convert adds one child entity per instance; the document lists the authored node.
        let loaded = try await loadModel(try instancedGLB(count: 4))
        #expect(loaded.document.nodes.count == 1)
        #expect(EntityLoader.modelComponentCount(in: loaded.entity) >= 4)
    }
}

// MARK: - Fixtures

/// Triangle mesh + two materials + one clip, with two extensions RealityKit cannot render.
private func ignoredExtensionGLB() throws -> Data {
    var bin = floatTriangleBin()
    let positionLength = bin.count
    appendFloats([0, 1], to: &bin)
    let timesOffset = positionLength
    appendFloats([0, 0, 0, 1, 0, 0], to: &bin)
    let valuesOffset = timesOffset + 8

    let json: [String: Any] = [
        "asset": ["version": "2.0"],
        "extensionsUsed": ["KHR_materials_volume", "KHR_materials_transmission"],
        "buffers": [["byteLength": bin.count]],
        "bufferViews": [
            ["buffer": 0, "byteOffset": 0, "byteLength": positionLength],
            ["buffer": 0, "byteOffset": timesOffset, "byteLength": 8],
            ["buffer": 0, "byteOffset": valuesOffset, "byteLength": 24],
        ],
        "accessors": [
            [
                "bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3",
                "max": [1, 1, 0], "min": [0, 0, 0],
            ],
            ["bufferView": 1, "componentType": 5126, "count": 2, "type": "SCALAR", "max": [1], "min": [0]],
            ["bufferView": 2, "componentType": 5126, "count": 2, "type": "VEC3"],
        ],
        "materials": [
            [
                "name": "Glass",
                "extensions": [
                    "KHR_materials_transmission": ["transmissionFactor": 1],
                    "KHR_materials_volume": ["thicknessFactor": 0.5, "attenuationDistance": 2],
                ],
            ],
            ["name": "Paint", "pbrMetallicRoughness": ["baseColorFactor": [1, 0, 0, 1]]],
        ],
        "meshes": [
            ["name": "BodyMesh", "primitives": [trianglePrimitive(material: 0)]],
            ["name": "TrimMesh", "primitives": [trianglePrimitive(material: 1)]],
        ],
        "nodes": [
            ["name": "Root", "children": [1, 2]],
            ["name": "Body", "mesh": 0],
            ["name": "Trim", "mesh": 1],
        ],
        "animations": [[
            "name": "Spin",
            "samplers": [["input": 1, "output": 2, "interpolation": "LINEAR"]],
            "channels": [["sampler": 0, "target": ["node": 1, "path": "translation"]]],
        ]],
        "scenes": [["name": "Default", "nodes": [0]]],
        "scene": 0,
    ]
    return try GLBBox.serialize(json: json, bin: bin)
}

private func specGlossGLB() throws -> Data {
    let bin = floatTriangleBin()
    let json: [String: Any] = [
        "asset": ["version": "2.0"],
        "extensionsUsed": ["KHR_materials_pbrSpecularGlossiness"],
        "buffers": [["byteLength": bin.count]],
        "bufferViews": [["buffer": 0, "byteOffset": 0, "byteLength": bin.count]],
        "accessors": [[
            "bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3",
            "max": [1, 1, 0], "min": [0, 0, 0],
        ]],
        "materials": [[
            "name": "Chrome",
            "extensions": [
                "KHR_materials_pbrSpecularGlossiness": [
                    "diffuseFactor": [0.25, 0.5, 0.75, 1],
                    "specularFactor": [1, 1, 1],
                    "glossinessFactor": 0.9,
                ],
            ],
        ]],
        "meshes": [["name": "Tri", "primitives": [trianglePrimitive(material: 0)]]],
        "nodes": [["name": "Root", "mesh": 0]],
        "scenes": [["nodes": [0]]],
        "scene": 0,
    ]
    return try GLBBox.serialize(json: json, bin: bin)
}
