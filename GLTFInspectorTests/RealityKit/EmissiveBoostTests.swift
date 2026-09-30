import Foundation
@testable import RendererRealityKit
import simd
@testable import GLTFCore
import Testing

struct EmissiveBoostTests {
    @Test func majorityAchromaticLooksBaked() {
        let junk = PreviewEmissive.Hint(factor: SIMD3(1, 1, 1), hasTexture: true)
        let hints = [junk, junk, junk, junk]
        #expect(PreviewEmissive.fileLooksBaked(hints))
        #expect(PreviewEmissive.shouldIgnore(junk, fileLooksBaked: true))
    }

    @Test func singleLampAmongManyIsKept() {
        var hints = Array(repeating: PreviewEmissive.Hint(), count: 8)
        hints[0] = PreviewEmissive.Hint(factor: SIMD3(1, 1, 1), hasTexture: true)
        #expect(!PreviewEmissive.fileLooksBaked(hints))
        #expect(!PreviewEmissive.shouldIgnore(hints[0], fileLooksBaked: false))
    }

    @Test func albedoCopyIsAlwaysIgnored() {
        let hint = PreviewEmissive.Hint(
            factor: SIMD3(1, 1, 1),
            hasTexture: true,
            sharesAlbedoTexture: true
        )
        #expect(PreviewEmissive.shouldIgnore(hint, fileLooksBaked: false))
    }

    @Test func chromaticGlowIsKept() {
        let hint = PreviewEmissive.Hint(factor: SIMD3(0.2, 0.4, 0.6))
        #expect(!hint.isAchromaticBoost)
        #expect(!PreviewEmissive.shouldIgnore(hint, fileLooksBaked: true))
    }

    @Test func highStrengthIsKept() {
        let hint = PreviewEmissive.Hint(factor: SIMD3(1, 1, 1), strength: 4, hasTexture: true)
        #expect(!hint.isAchromaticBoost)
        #expect(!PreviewEmissive.shouldIgnore(hint, fileLooksBaked: true))
    }

    @Test func punctualLightsDimStudioIBL() {
        #expect(RealityPolicy.studioIBLExponent(punctualLightCount: 0) == 0)
        #expect(RealityPolicy.studioIBLExponent(punctualLightCount: 1) == -2)
        #expect(!PreviewEmissive.fileLooksBaked(json: [
            "materials": [["pbrMetallicRoughness": ["metallicFactor": 0]]],
        ]))
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
        var look = RenderLook.standard
        #expect(abs(look.realityKitIBLYaw - .pi) < 1e-6)
        look.environmentYawDegrees = 90
        #expect(abs(look.realityKitIBLYaw - .pi / 2) < 1e-6)
        look.exposureEV = 1
        #expect(look.realityKitIBLExponent(fileHasLights: true) == -1)
        #expect(RealityLook.directionalIntensity(lux: 1) == 591)
        #expect(abs(RealityLook.pointIntensity(candela: 1) - 4 * .pi * 591) < 0.01)
        #expect(abs(RealityLook.spotIntensity(candela: 1) - .pi * 591) < 0.01)
        #expect(abs(RealityLook.spotConeDegrees(halfAngleRadians: .pi / 4) - 90) < 1e-4)
    }
}
