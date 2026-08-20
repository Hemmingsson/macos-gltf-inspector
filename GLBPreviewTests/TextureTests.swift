import AppKit
import CoreGraphics
import Foundation
import RealityKit
import Testing
import simd
@testable import GLBPreview

struct TextureAlphaUsageTests {
    @Test func constantZeroIsUnused() {
        #expect(TextureAlpha.usage(minAlpha: 0, maxAlpha: 0) == .unused)
    }

    @Test func constantOneIsUnused() {
        #expect(TextureAlpha.usage(minAlpha: 1, maxAlpha: 1) == .unused)
    }

    @Test func foliageSpanIsCutout() {
        #expect(TextureAlpha.usage(minAlpha: 0, maxAlpha: 1) == .cutout)
    }
}

struct TextureChannelExtractTests {
    /// macOS PNG decode is typically BGRA. glTF metal lives in B; RealityKit reads R.
    @Test func extractsBlueFromBGRA() throws {
        let image = try #require(Self.bgraImage(red: 255, green: 128, blue: 0))
        let context = RealityKitResourceContext()
        let extracted = try #require(context.singleChannelImage(from: image, channels: .blue))
        #expect(Self.grayPixel(extracted) == 0)
    }

    @Test func extractsGreenFromBGRA() throws {
        let image = try #require(Self.bgraImage(red: 255, green: 128, blue: 0))
        let context = RealityKitResourceContext()
        let extracted = try #require(context.singleChannelImage(from: image, channels: .green))
        #expect(Self.grayPixel(extracted) == 128)
    }

    private static func bgraImage(red: UInt8, green: UInt8, blue: UInt8) -> CGImage? {
        var pixel: [UInt8] = [blue, green, red, 255]
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let ctx = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: space,
            bitmapInfo: info
        ) else { return nil }
        return ctx.makeImage()
    }

    private static func grayPixel(_ image: CGImage) -> UInt8 {
        let data = image.dataProvider!.data!
        return CFDataGetBytePtr(data)[0]
    }
}

struct TextureUVTests {
    @Test func wrapsSingleNonZeroTile() {
        let uvs = [SIMD2<Float>(2.1, 3.2), SIMD2<Float>(2.8, 3.9)]
        let wrapped = TextureUV.wrapSingleTile(uvs)
        #expect(abs(wrapped[0].x - 0.1) < 0.0001)
        #expect(abs(wrapped[0].y - 0.2) < 0.0001)
        #expect(abs(wrapped[1].x - 0.8) < 0.0001)
        #expect(abs(wrapped[1].y - 0.9) < 0.0001)
    }

    @Test func leavesUnitSquareAlone() {
        let uvs = [SIMD2<Float>(0.01, 0.02), SIMD2<Float>(0.99, 0.98)]
        #expect(TextureUV.wrapSingleTile(uvs) == uvs)
    }

    @Test func leavesMultiTileSpanAlone() {
        let uvs = [SIMD2<Float>(0.1, 0.2), SIMD2<Float>(2.1, 0.2)]
        #expect(TextureUV.wrapSingleTile(uvs) == uvs)
    }

    @Test func leavesSlightNegativePaddingAlone() {
        let uvs = [SIMD2<Float>(-0.01, 0.1), SIMD2<Float>(0.9, 0.9)]
        #expect(TextureUV.wrapSingleTile(uvs) == uvs)
    }
}
