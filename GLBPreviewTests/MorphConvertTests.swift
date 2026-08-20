import Foundation
import RealityKit
import Testing
@testable import GLBPreview

struct MorphConvertTests {
    @MainActor
    @Test func convertsMorphTargetsAndWeightClip() async throws {
        let model = try await loadModel(try morphTriangleGLB(), includeAnimations: true)
        #expect(model.stats.morphGeometryCount == 1)
        #expect(firstComponent(BlendShapeWeightsComponent.self, in: model.entity) != nil)
        #expect(!model.entity.availableAnimations.isEmpty)
    }
}

/// One triangle, one POSITION morph target, one LINEAR weights clip 0 → 1.
private func morphTriangleGLB() throws -> Data {
    var bin = Data()
    appendFloats([0, 0, 0, 1, 0, 0, 0, 1, 0], to: &bin)
    let positionsLength = bin.count
    appendFloats([0, 0, 1, 0, 0, 0, 0, 0, 0], to: &bin)
    let targetLength = bin.count - positionsLength
    appendFloats([0, 1], to: &bin)
    let timesOffset = positionsLength + targetLength
    let timesLength = bin.count - timesOffset
    appendFloats([0, 1], to: &bin)
    let weightsOffset = timesOffset + timesLength
    let weightsLength = bin.count - weightsOffset

    let json: [String: Any] = [
        "asset": ["version": "2.0"],
        "buffers": [["byteLength": bin.count]],
        "bufferViews": [
            ["buffer": 0, "byteOffset": 0, "byteLength": positionsLength],
            ["buffer": 0, "byteOffset": positionsLength, "byteLength": targetLength],
            ["buffer": 0, "byteOffset": timesOffset, "byteLength": timesLength],
            ["buffer": 0, "byteOffset": weightsOffset, "byteLength": weightsLength],
        ],
        "accessors": [
            [
                "bufferView": 0,
                "componentType": 5126,
                "count": 3,
                "type": "VEC3",
                "min": [0, 0, 0],
                "max": [1, 1, 0],
            ],
            [
                "bufferView": 1,
                "componentType": 5126,
                "count": 3,
                "type": "VEC3",
            ],
            [
                "bufferView": 2,
                "componentType": 5126,
                "count": 2,
                "type": "SCALAR",
                "min": [0],
                "max": [1],
            ],
            [
                "bufferView": 3,
                "componentType": 5126,
                "count": 2,
                "type": "SCALAR",
            ],
        ],
        "meshes": [[
            "weights": [0],
            "extras": ["targetNames": ["Lift"]],
            "primitives": [[
                "attributes": ["POSITION": 0],
                "targets": [["POSITION": 1]],
                "mode": 4,
            ]],
        ]],
        "nodes": [["mesh": 0]],
        "animations": [[
            "name": "morph",
            "channels": [[
                "sampler": 0,
                "target": ["node": 0, "path": "weights"],
            ]],
            "samplers": [[
                "input": 2,
                "output": 3,
                "interpolation": "LINEAR",
            ]],
        ]],
        "scenes": [["nodes": [0]]],
        "scene": 0,
    ]
    return try GLBBox.serialize(json: json, bin: bin)
}
