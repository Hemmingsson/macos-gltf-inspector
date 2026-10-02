import AppKit
import GLTFKit2
import CoreGraphics
import Foundation
import ImageIO
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

/// Window convert binds a 1×1 placeholder; replace must keep that instance and land the same
/// pixels as the eager thumbnail path (no new goldens).
@MainActor
struct DeferredTextureReplaceTests {
    @Test func deferredReplaceKeepsResourceAndMatchesEagerPixels() async throws {
        let url = try TestGLB.writeTemp(try rasterQuadGLB(edge: 4), prefix: "tex-defer")
        defer { try? FileManager.default.removeItem(at: url) }

        let deferred = try await EntityLoader.load(from: url, includeAnimations: false)
        let material = try #require(pbrMaterials(in: deferred.entity).first)
        let resource = try #require(material.baseColor.texture?.resource)
        #expect(resource.width == 1)
        #expect(resource.height == 1)
        #expect(DeferredTextureReplace.job(on: deferred.entity)?.hasPending == true)

        await DeferredTextureReplace.finalize(attachedTo: deferred.entity)

        #expect(resource.width == 4)
        #expect(resource.height == 4)
        #expect(material.baseColor.texture?.resource === resource)
        #expect(DeferredTextureReplace.job(on: deferred.entity)?.hasPending == false)

        let eager = try await EntityLoader.loadThumbnail(from: url)
        let eagerResource = try #require(pbrMaterials(in: eager.entity).first?.baseColor.texture?.resource)
        #expect(eagerResource.width == 4)
        #expect(DeferredTextureReplace.job(on: eager.entity) == nil)

        let deferredPixels = try await renderTextureStill(deferred.entity)
        let eagerPixels = try await renderTextureStill(eager.entity)
        #expect(try PrepareFreeInputsTests.meanDifference(deferredPixels, eagerPixels) < 0.5)
    }
}

@MainActor
private func renderTextureStill(_ root: Entity) async throws -> CGImage {
    try await StillRenderer.render(
        root: root,
        cameraPose: StillCameraPose(
            position: [0.5, 0.5, 1.1],
            orientation: simd_quatf(angle: 0, axis: [0, 1, 0]),
            projection: .perspective(fieldOfViewDegrees: 45, near: 0.05, far: 10)
        ),
        width: 64,
        height: 64,
        background: CGColor(gray: 0.5, alpha: 1)
    )
}

/// PBR 4×N solid red quad so the 1×1 white placeholder is distinguishable from the final raster.
private func rasterQuadGLB(edge: Int) throws -> Data {
    var bin = Data()
    appendFloats([0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0], to: &bin)
    appendFloats([0, 1, 1, 1, 1, 0, 0, 0], to: &bin)
    for index: UInt16 in [0, 1, 2, 0, 2, 3] {
        var bits = index.littleEndian
        Swift.withUnsafeBytes(of: &bits) { bin.append(contentsOf: $0) }
    }
    let png = solidPNG(edge: edge, red: 200, green: 40, blue: 40)
    let imageOffset = bin.count
    bin.append(png)
    let json: [String: Any] = [
        "asset": ["version": "2.0"],
        "buffers": [["byteLength": bin.count]],
        "bufferViews": [
            ["buffer": 0, "byteOffset": 0, "byteLength": 48],
            ["buffer": 0, "byteOffset": 48, "byteLength": 32],
            ["buffer": 0, "byteOffset": 80, "byteLength": 12],
            ["buffer": 0, "byteOffset": imageOffset, "byteLength": png.count],
        ],
        "accessors": [
            ["bufferView": 0, "componentType": 5126, "count": 4, "type": "VEC3", "min": [0, 0, 0], "max": [1, 1, 0]],
            ["bufferView": 1, "componentType": 5126, "count": 4, "type": "VEC2"],
            ["bufferView": 2, "componentType": 5123, "count": 6, "type": "SCALAR"],
        ],
        "images": [["bufferView": 3, "mimeType": "image/png"]],
        "textures": [["source": 0]],
        "materials": [[
            "pbrMetallicRoughness": [
                "baseColorTexture": ["index": 0],
                "metallicFactor": 0,
                "roughnessFactor": 1,
            ],
        ]],
        "meshes": [["primitives": [[
            "attributes": ["POSITION": 0, "TEXCOORD_0": 1],
            "indices": 2,
            "material": 0,
        ]]]],
        "nodes": [["mesh": 0]],
        "scenes": [["nodes": [0]]],
        "scene": 0,
    ]
    return try TestGLB.serialize(json: json, bin: bin)
}

private func solidPNG(edge: Int, red: UInt8, green: UInt8, blue: UInt8) -> Data {
    var pixels = [UInt8](repeating: 0, count: edge * edge * 4)
    for i in stride(from: 0, to: pixels.count, by: 4) {
        pixels[i] = red
        pixels[i + 1] = green
        pixels[i + 2] = blue
        pixels[i + 3] = 255
    }
    let ctx = CGContext(
        data: &pixels,
        width: edge,
        height: edge,
        bitsPerComponent: 8,
        bytesPerRow: edge * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let data = NSMutableData()
    let dest = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
    return data as Data
}
