import Foundation
@testable import GLTFCore
@testable import GLTFInspector
import Testing

/// What the material inspector shows: a factor only when it differs from the glTF default.
struct MaterialDisplayTests {
    @Test func emissiveStrengthExtensionSurfacesInMaterialInfo() throws {
        let document = GLTFDocumentJSON.makeDocument(json: materialJSON(
            name: "Glow",
            extras: [
                "emissiveFactor": [1, 1, 1],
                "extensions": [
                    "KHR_materials_emissive_strength": ["emissiveStrength": 4],
                ],
            ]
        ))
        let strength = try #require(document.materials.first?.emissiveStrength)
        #expect(abs(strength - 4) < 0.0001)

        #expect(document.materials.first?.visibleEmissiveStrength == 4)
    }

    @Test func omittedEmissiveStrengthStaysNilAndHidden() throws {
        let document = GLTFDocumentJSON.makeDocument(json: materialJSON(name: "Matte"))
        #expect(document.materials.first?.emissiveStrength == nil)

        #expect(document.materials.first?.visibleEmissiveStrength == nil)
        let unit = GLTFDocumentJSON.makeDocument(json: materialJSON(name: "Unit", extras: [
            "extensions": ["KHR_materials_emissive_strength": ["emissiveStrength": 1]],
        ]))
        #expect(unit.materials.first?.emissiveStrength == 1)
        #expect(unit.materials.first?.visibleEmissiveStrength == nil)
    }

    /// A factor a map already covers is not repeated; a default factor is not shown.
    @Test func factorsHideWhenAMapCoversThemOrTheyAreDefault() throws {
        let plain = GLTFDocumentJSON.makeDocument(json: materialJSON(name: "Plain"))
        let material = try #require(plain.materials.first)
        #expect(material.visibleBaseColorFactor == nil)
        #expect(material.visibleMetallicFactor == nil)
        #expect(material.visibleRoughnessFactor == nil)

        let tinted = GLTFDocumentJSON.makeDocument(json: materialJSON(name: "Tinted", extras: [
            "pbrMetallicRoughness": ["baseColorFactor": [1, 0, 0, 1], "metallicFactor": 0],
        ]))
        #expect(tinted.materials.first?.visibleBaseColorFactor == SIMD4(1, 0, 0, 1))
        #expect(tinted.materials.first?.visibleMetallicFactor == 0)

        let mapped = GLTFDocumentJSON.makeDocument(json: materialJSON(name: "Mapped", extras: [
            "pbrMetallicRoughness": ["baseColorFactor": [1, 0, 0, 1], "baseColorTexture": ["index": 0]],
        ]))
        #expect(mapped.materials.first?.visibleBaseColorFactor == nil)
    }
}

private func materialJSON(name: String, extras: [String: Any] = [:]) -> [String: Any] {
    var material: [String: Any] = ["name": name]
    for (key, value) in extras {
        material[key] = value
    }
    return [
        "asset": ["version": "2.0"],
        "materials": [material],
        "nodes": [["name": "Root"]],
        "scenes": [["nodes": [0]]],
        "scene": 0,
    ]
}
