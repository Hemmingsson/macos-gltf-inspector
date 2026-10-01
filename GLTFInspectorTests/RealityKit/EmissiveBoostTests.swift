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

    @Test func iblExponentAddsExposureIntensityAndPolicyDim() {
        let dim = RealityPolicy.studioDimEV(fileHasLights: true)
        #expect(RealityLook.iblExponent(exposureEV: 0) == 0)
        #expect(RealityLook.iblExponent(exposureEV: 1) == 1)
        #expect(RealityLook.iblExponent(exposureEV: 0, dimEV: dim) == -2)
        #expect(RealityLook.iblExponent(exposureEV: 0.5, dimEV: dim) == -1.5)
        #expect(RealityLook.iblExponent(exposureEV: 0, environmentIntensity: 4) == 2)
    }

    /// Look-probe constants (seam 5): yaw 0 is the Khronos default view, lights × 591, spot × π
    /// with the full cone.
    @Test func renderLookMapsToRealityKitUnits() {
        #expect(abs(RealityLook.iblYaw(lookYawRadians: 0) - .pi) < 1e-6)
        #expect(abs(RealityLook.iblYaw(lookYawRadians: .pi / 2) - .pi / 2) < 1e-6)
        #expect(RealityLook.iblExponent(exposureEV: 1, dimEV: RealityPolicy.studioDimEV(fileHasLights: true)) == -1)
        #expect(RealityLook.directionalIntensity(lux: 1) == 591)
        #expect(abs(RealityLook.pointIntensity(candela: 1) - 4 * .pi * 591) < 0.01)
        #expect(abs(RealityLook.spotIntensity(candela: 1) - .pi * 591) < 0.01)
        #expect(abs(RealityLook.spotConeDegrees(halfAngleRadians: .pi / 4) - 90) < 1e-4)
    }
}
