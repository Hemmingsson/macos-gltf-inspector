import Foundation
import RealityKit
import Testing
import simd
@testable import GLBPreview

struct EmissiveBoostTests {
    @Test func majorityAchromaticLooksBaked() {
        let junk = GLBPreviewEmissive.Hint(factor: SIMD3(1, 1, 1), hasTexture: true)
        let hints = [junk, junk, junk, junk]
        #expect(GLBPreviewEmissive.fileLooksBaked(hints))
        #expect(GLBPreviewEmissive.shouldIgnore(junk, fileLooksBaked: true))
    }

    @Test func singleLampAmongManyIsKept() {
        var hints = Array(repeating: GLBPreviewEmissive.Hint(), count: 8)
        hints[0] = GLBPreviewEmissive.Hint(factor: SIMD3(1, 1, 1), hasTexture: true)
        #expect(!GLBPreviewEmissive.fileLooksBaked(hints))
        #expect(!GLBPreviewEmissive.shouldIgnore(hints[0], fileLooksBaked: false))
    }

    @Test func albedoCopyIsAlwaysIgnored() {
        let hint = GLBPreviewEmissive.Hint(
            factor: SIMD3(1, 1, 1),
            hasTexture: true,
            sharesAlbedoTexture: true
        )
        #expect(GLBPreviewEmissive.shouldIgnore(hint, fileLooksBaked: false))
    }

    @Test func chromaticGlowIsKept() {
        let hint = GLBPreviewEmissive.Hint(factor: SIMD3(0.2, 0.4, 0.6))
        #expect(!hint.isAchromaticBoost)
        #expect(!GLBPreviewEmissive.shouldIgnore(hint, fileLooksBaked: true))
    }

    @Test func highStrengthIsKept() {
        let hint = GLBPreviewEmissive.Hint(factor: SIMD3(1, 1, 1), strength: 4, hasTexture: true)
        #expect(!hint.isAchromaticBoost)
        #expect(!GLBPreviewEmissive.shouldIgnore(hint, fileLooksBaked: true))
    }

    @Test func punctualLightsDimStudioIBL() {
        #expect(GLBPreviewEmissive.studioIBLExponent(punctualLightCount: 0) == 0)
        #expect(GLBPreviewEmissive.studioIBLExponent(punctualLightCount: 1) == -2)
        #expect(!GLBPreviewEmissive.fileLooksBaked(json: [
            "materials": [["pbrMetallicRoughness": ["metallicFactor": 0]]],
        ]))
    }

    @MainActor
    @Test func sketchfabExportsDropBakedEmissive() async throws {
        let paths = [
            "/Users/mattias/Downloads/Radio_Device_-_HDAVD_9387-64cb9916.glb",
            "/Users/mattias/Downloads/The_Whole_World-712c2de7.glb",
            "/Users/mattias/Downloads/hippie-mobile.glb",
        ]
        var checked = 0
        for path in paths where FileManager.default.fileExists(atPath: path) {
            let model = try await GLBEntityLoader.load(from: URL(fileURLWithPath: path), includeAnimations: false)
            let materials = pbrMaterials(in: model.entity)
            try #require(!materials.isEmpty)
            for material in materials {
                #expect(!hasVisibleEmissive(material), "\(URL(fileURLWithPath: path).lastPathComponent) still emits")
            }
            #expect(model.usesBakedEmissive)
            #expect(model.studioIBLExponent == 0)
            checked += 1
        }
        try #require(checked > 0)
    }
}

private func hasVisibleEmissive(_ material: PhysicallyBasedMaterial) -> Bool {
    if material.emissiveColor.texture != nil { return true }
    guard let components = material.emissiveColor.color.cgColor.components, components.count >= 3 else {
        return false
    }
    return max(components[0], max(components[1], components[2])) > 0.05
}

private func pbrMaterials(in entity: Entity) -> [PhysicallyBasedMaterial] {
    var out: [PhysicallyBasedMaterial] = []
    if let model = entity.components[ModelComponent.self] {
        for material in model.materials {
            if let pbr = material as? PhysicallyBasedMaterial {
                out.append(pbr)
            }
        }
    }
    for child in entity.children {
        out.append(contentsOf: pbrMaterials(in: child))
    }
    return out
}
