import Foundation
@testable import GLTFCore
import simd
import Testing

/// `ModelBounds.from(json:)`: accessor min/max × node transforms, from the JSON alone. Checked
/// against RealityKit's entity bounds over the whole corpus in
/// `RealityKit/JSONModelBoundsRealityKitTests.swift`.
struct JSONModelBoundsTests {
    @Test func quantizedPositionsAreDequantized() {
        let json: [String: Any] = [
            "scenes": [["nodes": [0]]],
            "nodes": [["mesh": 0, "scale": [2, 2, 2]]],
            "meshes": [["primitives": [["attributes": ["POSITION": 0]]]]],
            "accessors": [[
                "componentType": 5122, "normalized": true, "type": "VEC3", "count": 2,
                "min": [-32767, 0, -32767], "max": [32767, 32767, 32767],
            ]],
        ]
        let bounds = ModelBounds.from(json: json)
        #expect(bounds?.min == SIMD3(-2, 0, -2))
        #expect(bounds?.max == SIMD3(2, 2, 2))
    }

    @Test func noMeshesMeansNoBounds() {
        #expect(ModelBounds.from(json: ["nodes": [["name": "empty"]]]) == nil)
    }
}
