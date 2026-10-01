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
        let context = try RealityKitResourceContext()
        let roughness = try #require(context.texture(for: params, channels: .green, semantic: .scalar))
        let metallic = try #require(context.texture(for: params, channels: .blue, semantic: .scalar))
        #expect(roughness.resource === metallic.resource)
        #expect(roughness.swizzle.red == .green)
        #expect(metallic.swizzle.red == .blue)
    }

    @Test func opacityReusesTheBaseColorUpload() throws {
        let params = try Self.params(red: 10, green: 20, blue: 30)
        let context = try RealityKitResourceContext()
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
