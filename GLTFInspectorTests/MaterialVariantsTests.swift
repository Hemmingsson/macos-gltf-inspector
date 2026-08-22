import Foundation
import GLTFKit2
import RealityKit
import Testing
@testable import GLTFInspector

struct MaterialVariantsTests {
    @Test func gltfKit2ExposesVariantNamesAndMappings() throws {
        let url = try writeTempMaterialsVariantsGLB()
        defer { try? FileManager.default.removeItem(at: url) }

        let asset = try GLTFAsset(
            url: url,
            options: [GLTFAssetLoadingOption.assetDirectoryURLKey: url.deletingLastPathComponent()]
        )
        #expect(MaterialVariants.names(from: asset) == ["Red", "Blue"])
        #expect(MaterialVariants.hasMappings(in: asset))

        let primitive = try #require(asset.meshes.first?.primitives.first)
        #expect((primitive.materialMappings ?? []).count == 2)
        #expect(primitive.material?.name == "RedMat")

        MaterialVariants.apply(variantIndex: 1, to: asset)
        #expect(primitive.material?.name == "BlueMat")

        MaterialVariants.apply(variantIndex: 0, to: asset)
        #expect(primitive.material?.name == "RedMat")
    }

    @MainActor
    @Test func loaderSurfacesVariantNamesAndAppliesMapping() async throws {
        let url = try writeTempMaterialsVariantsGLB()
        defer { try? FileManager.default.removeItem(at: url) }

        let defaultModel = try await EntityLoader.load(from: url, includeAnimations: false)
        #expect(defaultModel.materialVariantNames == ["Red", "Blue"])

        let blue = try await EntityLoader.load(
            from: url,
            includeAnimations: false,
            materialVariantIndex: 1
        )
        #expect(blue.materialVariantNames == ["Red", "Blue"])
        #expect(EntityLoader.modelComponentCount(in: blue.entity) > 0)
    }
}

private func writeTempMaterialsVariantsGLB() throws -> URL {
    var bin = Data()
    appendFloats([0, 0, 0, 1, 0, 0, 0, 1, 0], to: &bin)
    let json: [String: Any] = [
        "asset": ["version": "2.0"],
        "extensionsUsed": ["KHR_materials_variants"],
        "extensions": [
            "KHR_materials_variants": [
                "variants": [
                    ["name": "Red"],
                    ["name": "Blue"],
                ],
            ],
        ],
        "buffers": [["byteLength": bin.count]],
        "bufferViews": [["buffer": 0, "byteOffset": 0, "byteLength": bin.count]],
        "accessors": [[
            "bufferView": 0,
            "componentType": 5126,
            "count": 3,
            "type": "VEC3",
            "max": [1, 1, 0],
            "min": [0, 0, 0],
        ]],
        "materials": [
            [
                "name": "RedMat",
                "pbrMetallicRoughness": ["baseColorFactor": [1, 0, 0, 1]],
            ],
            [
                "name": "BlueMat",
                "pbrMetallicRoughness": ["baseColorFactor": [0, 0, 1, 1]],
            ],
        ],
        "meshes": [[
            "name": "Tri",
            "primitives": [[
                "attributes": ["POSITION": 0],
                "material": 0,
                "extensions": [
                    "KHR_materials_variants": [
                        "mappings": [
                            ["material": 0, "variants": [0]],
                            ["material": 1, "variants": [1]],
                        ],
                    ],
                ],
            ]],
        ]],
        "nodes": [["name": "Root", "mesh": 0]],
        "scenes": [["nodes": [0]]],
        "scene": 0,
    ]
    return try GLBBox.writePrepared(try GLBBox.serialize(json: json, bin: bin), prefix: "variants")
}
