import Foundation
@testable import GLTFCore
@testable import GLTFInspector
import PreviewUI
import Testing

/// Host mapping of file materials — JSON document → `MaterialInfo`, no renderer convert.
struct EngineSceneModelMaterialTests {
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

        let material = try #require(mappedMaterial(document))
        let mapped = try #require(material.emissiveStrength)
        #expect(abs(mapped - 4) < 0.0001)
        #expect(MaterialInspectorSupport.showsEmissiveStrength(material))
    }

    @Test func omittedEmissiveStrengthStaysNilAndHidden() throws {
        let document = GLTFDocumentJSON.makeDocument(json: materialJSON(name: "Matte"))
        #expect(document.materials.first?.emissiveStrength == nil)

        let material = try #require(mappedMaterial(document))
        #expect(material.emissiveStrength == nil)
        #expect(!MaterialInspectorSupport.showsEmissiveStrength(material))
        #expect(!MaterialInspectorSupport.showsEmissiveStrength(
            MaterialInfo(index: 0, name: "Default", emissiveStrength: 1)
        ))
    }
}

private func mappedMaterial(_ document: GLTFSessionDocument) -> MaterialInfo? {
    EngineSceneModel(
        fileName: "emissive.gltf",
        document: document,
        stats: .empty,
        dimensions: Dimensions(width: 0, height: 0, depth: 0)
    ).materials.first
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
