import AppKit
import CoreGraphics
import Foundation
import RealityKit
@testable import RendererRealityKit
import simd
import Testing

struct SpecGlossTests {
    @Test func bakeGateIsPolicy() {
        #expect(RealityPolicy.bakesSpecGlossTextures(imageCount: 40, texturedMaterialCount: 24))
        #expect(!RealityPolicy.bakesSpecGlossTextures(imageCount: 41, texturedMaterialCount: 1))
        #expect(!RealityPolicy.bakesSpecGlossTextures(imageCount: 1, texturedMaterialCount: 25))
    }

    @Test func downsamplesLongestEdge() {
        let source = PixelImage(width: 2048, height: 1024, bytes: [UInt8](repeating: 255, count: 2048 * 1024 * 4))
        let scaled = source.downsampled(maxEdge: 1024)
        #expect(scaled.width == 1024)
        #expect(scaled.height == 512)
    }
}
