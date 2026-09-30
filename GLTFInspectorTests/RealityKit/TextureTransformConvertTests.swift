import CoreGraphics
import Foundation
import ImageIO
@testable import GLTFCore
import RealityKit
@testable import RendererRealityKit
import simd
import Testing

/// `KHR_texture_transform` must look exactly like the same UVs pre-transformed in the file.
/// The quad samples a 4-colour 2×2 texture (NEAREST, REPEAT), unlit, filling the frame.
@MainActor
struct TextureTransformConvertTests {
    static let offset = SIMD2<Float>(0.2, 0.1)
    static let rotation: Float = 0.3
    static let scale = SIMD2<Float>(1.5, 0.8)

    @Test func transformMatchesPretransformedUVs() async throws {
        let transformed = try await loadModel(try transformQuadGLB(bake: false, texCoord: 0))
        let baked = try await loadModel(try transformQuadGLB(bake: true, texCoord: 0))
        let a = try await Self.render(transformed.entity)
        let b = try await Self.render(baked.entity)
        #expect(try PrepareFreeInputsTests.meanDifference(a, b) < 0.5)
        // And the transform is visible at all: the untransformed quad looks different.
        let plain = try await loadModel(try transformQuadGLB(bake: false, texCoord: 0, transform: false))
        #expect(try PrepareFreeInputsTests.meanDifference(a, try await Self.render(plain.entity)) > 5)
    }

    /// Same, with the texture on TEXCOORD_1 (TEXCOORD_0 is a decoy of zeros) of a lit material
    /// (`UnlitMaterial` has no secondary transform).
    @Test func secondUVSetWithTransform() async throws {
        let transformed = try await loadModel(try transformQuadGLB(bake: false, texCoord: 1, unlit: false))
        let baked = try await loadModel(try transformQuadGLB(bake: true, texCoord: 0, unlit: false))
        let a = try await Self.render(transformed.entity)
        let b = try await Self.render(baked.entity)
        #expect(try PrepareFreeInputsTests.meanDifference(a, b) < 0.5)
    }

    static func render(_ root: Entity) async throws -> CGImage {
        let still = try await StillRenderer(
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
        return try await still.capture()
    }

    /// glTF `uv' = T · R · S · uv`, as the spec writes it.
    static func gltfTransform(_ uv: SIMD2<Float>) -> SIMD2<Float> {
        let s = uv * scale
        let c = cos(rotation), n = sin(rotation)
        return SIMD2(c * s.x + n * s.y, -n * s.x + c * s.y) + offset
    }
}

private func transformQuadGLB(bake: Bool, texCoord: Int, transform: Bool = true, unlit: Bool = true) throws -> Data {
    let uvs: [SIMD2<Float>] = [[0, 1], [1, 1], [1, 0], [0, 0]]
    let authored = bake ? uvs.map(TextureTransformConvertTests.gltfTransform) : uvs
    var bin = Data()
    appendFloats([0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0], to: &bin)
    appendFloats(texCoord == 1 ? [Float](repeating: 0, count: 8) : authored.flatMap { [$0.x, $0.y] }, to: &bin)
    appendFloats(authored.flatMap { [$0.x, $0.y] }, to: &bin)
    for index: UInt16 in [0, 1, 2, 0, 2, 3] {
        var bits = index.littleEndian
        Swift.withUnsafeBytes(of: &bits) { bin.append(contentsOf: $0) }
    }
    let png = quadrantPNG()
    let imageOffset = bin.count
    bin.append(png)
    var info: [String: Any] = ["index": 0, "texCoord": texCoord]
    if !bake && transform {
        info["extensions"] = ["KHR_texture_transform": [
            "offset": [TextureTransformConvertTests.offset.x, TextureTransformConvertTests.offset.y],
            "rotation": TextureTransformConvertTests.rotation,
            "scale": [TextureTransformConvertTests.scale.x, TextureTransformConvertTests.scale.y],
        ]]
    }
    let json: [String: Any] = [
        "asset": ["version": "2.0"],
        "extensionsUsed": ["KHR_texture_transform", "KHR_materials_unlit"],
        "buffers": [["byteLength": bin.count]],
        "bufferViews": [
            ["buffer": 0, "byteOffset": 0, "byteLength": 48],
            ["buffer": 0, "byteOffset": 48, "byteLength": 32],
            ["buffer": 0, "byteOffset": 80, "byteLength": 32],
            ["buffer": 0, "byteOffset": 112, "byteLength": 12],
            ["buffer": 0, "byteOffset": imageOffset, "byteLength": png.count],
        ],
        "accessors": [
            ["bufferView": 0, "componentType": 5126, "count": 4, "type": "VEC3", "min": [0, 0, 0], "max": [1, 1, 0]],
            ["bufferView": 1, "componentType": 5126, "count": 4, "type": "VEC2"],
            ["bufferView": 2, "componentType": 5126, "count": 4, "type": "VEC2"],
            ["bufferView": 3, "componentType": 5123, "count": 6, "type": "SCALAR"],
        ],
        "images": [["bufferView": 4, "mimeType": "image/png"]],
        "samplers": [["magFilter": 9728, "minFilter": 9728, "wrapS": 10497, "wrapT": 10497]],
        "textures": [["source": 0, "sampler": 0]],
        "materials": [unlit
            ? ["pbrMetallicRoughness": ["baseColorTexture": info], "extensions": ["KHR_materials_unlit": [:]]]
            : ["pbrMetallicRoughness": ["baseColorTexture": info, "metallicFactor": 0]],
        ],
        "meshes": [["primitives": [[
            "attributes": ["POSITION": 0, "TEXCOORD_0": 1, "TEXCOORD_1": 2],
            "indices": 3,
            "material": 0,
        ]]]],
        "nodes": [["mesh": 0]],
        "scenes": [["nodes": [0]]],
        "scene": 0,
    ]
    return try TestGLB.serialize(json: json, bin: bin)
}

/// 2×2 PNG: red, green / blue, yellow.
private func quadrantPNG() -> Data {
    var pixels: [UInt8] = [255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 0, 255]
    let ctx = CGContext(
        data: &pixels, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let data = NSMutableData()
    let dest = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
    return data as Data
}
