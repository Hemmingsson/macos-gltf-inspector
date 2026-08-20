import AppKit
import CoreGraphics
import Foundation
import RealityKit
import Testing
import simd
@testable import GLBPreview

struct SpecGlossTests {
    @Test func needsConversionWhenExtensionPresent() {
        let json: [String: Any] = [
            "materials": [
                ["extensions": ["KHR_materials_pbrSpecularGlossiness": ["glossinessFactor": 1]]],
            ],
        ]
        #expect(MetalRoughPrepare.needsConversion(json))
    }

    @Test func skipsMetalRoughOnly() {
        let json: [String: Any] = [
            "materials": [
                ["pbrMetallicRoughness": ["metallicFactor": 0]],
            ],
        ]
        #expect(!MetalRoughPrepare.needsConversion(json))
    }

    @Test func skipsBakeWhenTooManyImages() {
        let images = Array(repeating: ["mimeType": "image/png"], count: 41)
        let materials: [[String: Any]] = [
            ["extensions": ["KHR_materials_pbrSpecularGlossiness": ["specularGlossinessTexture": ["index": 0]]]],
        ]
        #expect(!MetalRoughPrepare.shouldBakeTextures(json: ["images": images], materials: materials))
    }

    @Test func downsamplesLongestEdge() {
        let source = PixelImage(width: 2048, height: 1024, bytes: [UInt8](repeating: 255, count: 2048 * 1024 * 4))
        let scaled = source.downsampled(maxEdge: 1024)
        #expect(scaled.width == 1024)
        #expect(scaled.height == 512)
    }
}
