import AppKit
import GLTFKit2
import CoreGraphics
import Foundation
import RealityKit
@testable import RendererRealityKit
import simd
import Testing

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

/// Single glTF channels (metallic in B, roughness in G, occlusion in R, alpha) are read from one
/// upload per image through `Texture.swizzle`; RealityKit reads R for scalar inputs.
@MainActor
struct TextureChannelSwizzleTests {
    @Test func metallicAndRoughnessShareOneUpload() throws {
        let params = try Self.params(red: 255, green: 128, blue: 0)
        let context = RealityKitResourceContext()
        let roughness = try #require(context.texture(for: params, channels: .green, semantic: .scalar))
        let metallic = try #require(context.texture(for: params, channels: .blue, semantic: .scalar))
        #expect(roughness.resource === metallic.resource)
        #expect(roughness.swizzle.red == .green)
        #expect(metallic.swizzle.red == .blue)
    }

    @Test func opacityReusesTheBaseColorUpload() throws {
        let params = try Self.params(red: 10, green: 20, blue: 30)
        let context = RealityKitResourceContext()
        let base = try #require(context.texture(for: params, channels: .all, semantic: .color))
        let alpha = try #require(context.texture(for: params, channels: .alpha, semantic: .scalar))
        #expect(base.resource === alpha.resource)
        #expect(alpha.swizzle.red == .alpha)
    }

    private static func params(red: UInt8, green: UInt8, blue: UInt8) throws -> GLTFTextureParams {
        var pixel: [UInt8] = [blue, green, red, 255]
        let info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        let ctx = try #require(CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info
        ))
        let image = try #require(ctx.makeImage())
        let params = GLTFTextureParams()
        params.texture = GLTFTexture(source: GLTFImage(cgImage: image))
        return params
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
