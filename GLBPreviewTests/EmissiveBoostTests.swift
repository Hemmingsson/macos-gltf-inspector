import Foundation
import Testing
import simd
@testable import GLBPreview

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
        #expect(PreviewEmissive.studioIBLExponent(punctualLightCount: 0) == 0)
        #expect(PreviewEmissive.studioIBLExponent(punctualLightCount: 1) == -2)
        #expect(!PreviewEmissive.fileLooksBaked(json: [
            "materials": [["pbrMetallicRoughness": ["metallicFactor": 0]]],
        ]))
    }

    @Test func sessionIBLExponentAddsExposureEV() {
        #expect(PreviewEmissive.sessionIBLExponent(dimStudioForFileLights: false, exposureEV: 0) == 0)
        #expect(PreviewEmissive.sessionIBLExponent(dimStudioForFileLights: false, exposureEV: 1) == 1)
        #expect(PreviewEmissive.sessionIBLExponent(dimStudioForFileLights: true, exposureEV: 0) == -2)
        #expect(PreviewEmissive.sessionIBLExponent(dimStudioForFileLights: true, exposureEV: 0.5) == -1.5)
    }
}
