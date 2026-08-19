import Foundation
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
}
