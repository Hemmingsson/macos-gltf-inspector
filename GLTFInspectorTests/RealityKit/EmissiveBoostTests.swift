import Foundation
@testable import RendererRealityKit
import simd
@testable import GLTFCore
import Testing

struct EmissiveBoostTests {
    @Test func majorityAchromaticLooksBaked() {
        let junk = RealityPolicy.EmissiveHint(factor: SIMD3(1, 1, 1), hasTexture: true)
        let hints = [junk, junk, junk, junk]
        #expect(RealityPolicy.fileLooksBaked(hints))
        #expect(RealityPolicy.dropsEmissive(junk, fileLooksBaked: true))
    }

    @Test func singleLampAmongManyIsKept() {
        var hints = Array(repeating: RealityPolicy.EmissiveHint(), count: 8)
        hints[0] = RealityPolicy.EmissiveHint(factor: SIMD3(1, 1, 1), hasTexture: true)
        #expect(!RealityPolicy.fileLooksBaked(hints))
        #expect(!RealityPolicy.dropsEmissive(hints[0], fileLooksBaked: false))
    }

    @Test func albedoCopyIsAlwaysIgnored() {
        let hint = RealityPolicy.EmissiveHint(
            factor: SIMD3(1, 1, 1),
            hasTexture: true,
            sharesAlbedoTexture: true
        )
        #expect(RealityPolicy.dropsEmissive(hint, fileLooksBaked: false))
    }

    @Test func chromaticGlowIsKept() {
        let hint = RealityPolicy.EmissiveHint(factor: SIMD3(0.2, 0.4, 0.6))
        #expect(!hint.isAchromaticBoost)
        #expect(!RealityPolicy.dropsEmissive(hint, fileLooksBaked: true))
    }

    @Test func highStrengthIsKept() {
        let hint = RealityPolicy.EmissiveHint(factor: SIMD3(1, 1, 1), strength: 4, hasTexture: true)
        #expect(!hint.isAchromaticBoost)
        #expect(!RealityPolicy.dropsEmissive(hint, fileLooksBaked: true))
    }

    /// The policy runs inside convert but is reported: an emissive copy of the albedo is dropped
    /// and listed as a convert problem.
    @MainActor
    @Test func albedoCopyDropIsReported() async throws {
        let glb = try texturedPBRTriangleGLB(
            material: [
                "pbrMetallicRoughness": ["baseColorTexture": ["index": 0]],
                "emissiveTexture": ["index": 0],
                "emissiveFactor": [1, 1, 1],
            ],
            uvs: [(0, 0), (1, 0), (0, 1)]
        )
        let model = try await loadModel(glb)
        #expect(model.convertProblems.items.contains { $0.code == .droppedEmissive })
        let material = try #require(pbrMaterials(in: model.entity).first)
        #expect(material.emissiveColor.texture == nil)
    }

    @Test func punctualLightsDimStudioIBL() {
        #expect(RealityPolicy.studioIBLExponent(punctualLightCount: 0) == 0)
        #expect(RealityPolicy.studioIBLExponent(punctualLightCount: 1) == -2)
    }
}
