import CoreGraphics
import Foundation
@testable import GLTFCore
import RealityKit
@testable import RendererRealityKit
import simd
import Testing

/// Inputs the old temp-GLB prepare pass used to rewrite (WebP → PNG, unnamed skin joints) must
/// load and render straight from GLTFKit2: it decodes `EXT_texture_webp` with ImageIO, and convert
/// resolves joint names itself (`Skin.resolvedName`).
@MainActor
struct PrepareFreeInputsTests {
    /// A quad whose only texture is WebP (no PNG fallback), unlit, solid (200, 40, 40).
    @Test func webpOnlyTextureRenders() async throws {
        let model = try await loadModel(try webpQuadGLB())
        #expect(model.convertProblems.isEmpty, "\(model.convertProblems.hostSummary)")
        let center = try Self.centerPixel(of: try await Self.render(model.entity, eye: [0.5, 0.5, 2]))
        #expect(center.r > 150 && center.g < 90 && center.b < 90, "center = \(center)")
    }

    /// A skinned triangle bound to two unnamed joints, with a clip moving the second joint +X.
    /// The skeleton must get distinct joint names and the clip must move the mesh.
    @Test func unnamedJointsSkinAndAnimate() async throws {
        let model = try await loadModel(try unnamedJointSkinGLB(), includeAnimations: true)
        let mesh = try #require(firstComponent(ModelComponent.self, in: model.entity)?.mesh)
        let joints = mesh.contents.skeletons.first?.joints.map(\.name) ?? []
        #expect(joints.count == 2)
        #expect(Set(joints).count == 2)
        #expect(joints.allSatisfy { !$0.isEmpty })

        let clip = try #require(model.entity.availableAnimations.first)
        let controller = model.entity.playAnimation(clip, startsPaused: true)
        controller.time = 0
        let before = try await Self.render(model.entity, eye: [1, 1.5, 5])
        controller.time = 1
        let after = try await Self.render(model.entity, eye: [1, 1.5, 5])
        #expect(try Self.meanDifference(before, after) > 0.3, "skinned triangle did not move")
    }

    @Test func unnamedJointsResolveBySkinIndex() {
        #expect(Skin.resolvedName(nil, index: 4) == "joint-4")
        #expect(Skin.resolvedName("Root", index: 4) == "Root")
    }

    static func render(_ root: Entity, eye: SIMD3<Float>) async throws -> CGImage {
        let still = try await StillRenderer(
            root: root,
            cameraPose: StillCameraPose(
                position: eye,
                orientation: simd_quatf(angle: 0, axis: [0, 1, 0]),
                projection: .perspective(fieldOfViewDegrees: 45, near: 0.05, far: 100)
            ),
            width: 64,
            height: 64,
            background: CGColor(gray: 0.5, alpha: 1)
        )
        return try await still.capture()
    }

    static func centerPixel(of image: CGImage) throws -> (r: Int, g: Int, b: Int) {
        let raster = try PixelDiff.raster(from: image)
        let i = ((image.height / 2) * image.width + image.width / 2) * 4
        return (Int(raster.bytes[i]), Int(raster.bytes[i + 1]), Int(raster.bytes[i + 2]))
    }

    static func meanDifference(_ a: CGImage, _ b: CGImage) throws -> Double {
        let x = try PixelDiff.raster(from: a), y = try PixelDiff.raster(from: b)
        var sum = 0
        for i in 0..<x.bytes.count { sum += abs(Int(x.bytes[i]) - Int(y.bytes[i])) }
        return Double(sum) / Double(x.bytes.count)
    }
}

/// 4×4 lossless WebP, solid sRGB (200, 40, 40) (`cwebp -lossless`).
private let redWebP = Data(base64Encoded: "UklGRh4AAABXRUJQVlA4TBEAAAAvA8AAAAdQlCIXpf+BiOh/AAA=")!

private func webpQuadGLB() throws -> Data {
    var bin = Data()
    appendFloats([0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0], to: &bin)
    appendFloats([0, 1, 1, 1, 1, 0, 0, 0], to: &bin)
    for index: UInt16 in [0, 1, 2, 0, 2, 3] {
        var bits = index.littleEndian
        Swift.withUnsafeBytes(of: &bits) { bin.append(contentsOf: $0) }
    }
    let imageOffset = bin.count
    bin.append(redWebP)
    let json: [String: Any] = [
        "asset": ["version": "2.0"],
        "extensionsUsed": ["EXT_texture_webp", "KHR_materials_unlit"],
        "extensionsRequired": ["EXT_texture_webp"],
        "buffers": [["byteLength": bin.count]],
        "bufferViews": [
            ["buffer": 0, "byteOffset": 0, "byteLength": 48],
            ["buffer": 0, "byteOffset": 48, "byteLength": 32],
            ["buffer": 0, "byteOffset": 80, "byteLength": 12],
            ["buffer": 0, "byteOffset": imageOffset, "byteLength": redWebP.count],
        ],
        "accessors": [
            ["bufferView": 0, "componentType": 5126, "count": 4, "type": "VEC3", "min": [0, 0, 0], "max": [1, 1, 0]],
            ["bufferView": 1, "componentType": 5126, "count": 4, "type": "VEC2"],
            ["bufferView": 2, "componentType": 5123, "count": 6, "type": "SCALAR"],
        ],
        "images": [["bufferView": 3, "mimeType": "image/webp"]],
        "textures": [["extensions": ["EXT_texture_webp": ["source": 0]]]],
        "materials": [[
            "pbrMetallicRoughness": ["baseColorTexture": ["index": 0]],
            "extensions": ["KHR_materials_unlit": [:]],
        ]],
        "meshes": [["primitives": [["attributes": ["POSITION": 0, "TEXCOORD_0": 1], "indices": 2, "material": 0]]]],
        "nodes": [["mesh": 0]],
        "scenes": [["nodes": [0]]],
        "scene": 0,
    ]
    return try TestGLB.serialize(json: json, bin: bin)
}

/// Skinned triangle, all weight on joint 1; joints 1 and 2 have no names. One clip translates
/// joint 2 from (0, 1, 0) to (1.5, 1, 0).
private func unnamedJointSkinGLB() throws -> Data {
    var bin = floatTriangleBin()
    let jointsOffset = bin.count
    for _ in 0..<3 {
        for value: UInt16 in [1, 0, 0, 0] {
            var bits = value.littleEndian
            Swift.withUnsafeBytes(of: &bits) { bin.append(contentsOf: $0) }
        }
    }
    let weightsOffset = bin.count
    appendFloats([1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0], to: &bin)
    let ibmOffset = bin.count
    appendFloats([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1], to: &bin)
    appendFloats([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, -1, 0, 1], to: &bin)
    let timesOffset = bin.count
    appendFloats([0, 1], to: &bin)
    let valuesOffset = bin.count
    appendFloats([0, 1, 0, 1.5, 1, 0], to: &bin)
    let json: [String: Any] = [
        "asset": ["version": "2.0"],
        "buffers": [["byteLength": bin.count]],
        "bufferViews": [
            ["buffer": 0, "byteOffset": 0, "byteLength": jointsOffset],
            ["buffer": 0, "byteOffset": jointsOffset, "byteLength": weightsOffset - jointsOffset],
            ["buffer": 0, "byteOffset": weightsOffset, "byteLength": ibmOffset - weightsOffset],
            ["buffer": 0, "byteOffset": ibmOffset, "byteLength": timesOffset - ibmOffset],
            ["buffer": 0, "byteOffset": timesOffset, "byteLength": 8],
            ["buffer": 0, "byteOffset": valuesOffset, "byteLength": 24],
        ],
        "accessors": [
            ["bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [0, 0, 0], "max": [1, 1, 0]],
            ["bufferView": 1, "componentType": 5123, "count": 3, "type": "VEC4"],
            ["bufferView": 2, "componentType": 5126, "count": 3, "type": "VEC4"],
            ["bufferView": 3, "componentType": 5126, "count": 2, "type": "MAT4"],
            ["bufferView": 4, "componentType": 5126, "count": 2, "type": "SCALAR", "min": [0], "max": [1]],
            ["bufferView": 5, "componentType": 5126, "count": 2, "type": "VEC3"],
        ],
        "meshes": [["primitives": [["attributes": ["POSITION": 0, "JOINTS_0": 1, "WEIGHTS_0": 2]]]]],
        "skins": [["joints": [1, 2], "inverseBindMatrices": 3]],
        "nodes": [
            ["mesh": 0, "skin": 0, "children": [1]],
            ["children": [2]],
            ["translation": [0, 1, 0]],
        ],
        "animations": [[
            "samplers": [["input": 4, "output": 5, "interpolation": "LINEAR"]],
            "channels": [["sampler": 0, "target": ["node": 2, "path": "translation"]]],
        ]],
        "scenes": [["nodes": [0]]],
        "scene": 0,
    ]
    return try TestGLB.serialize(json: json, bin: bin)
}

/// `KHR_mesh_quantization` no longer goes through a dequantize rewrite: the LowLevelMesh path
/// takes a packed float copy. A quantized quad (SHORT positions, normalized BYTE normals,
/// normalized USHORT UVs) must render exactly like its float twin.
@MainActor
struct QuantizedMeshTests {
    @Test func quantizedQuadRendersLikeFloatQuad() async throws {
        let quantized = try await loadModel(try quadGLB(quantized: true))
        let float = try await loadModel(try quadGLB(quantized: false))
        let eye: SIMD3<Float> = [0.5, 0.5, 2]
        let a = try await PrepareFreeInputsTests.render(quantized.entity, eye: eye)
        let b = try await PrepareFreeInputsTests.render(float.entity, eye: eye)
        #expect(try PrepareFreeInputsTests.meanDifference(a, b) < 0.05)
        // Not just two empty frames: the red quad covers the centre.
        let center = try PrepareFreeInputsTests.centerPixel(of: a)
        #expect(center.r > center.g + 40, "center = \(center)")
    }

    @Test func quantizedPositionsKeepTheirRawUnits() async throws {
        let model = try await loadModel(try shortTriangleGLB())
        let bounds = model.entity.visualBounds(relativeTo: nil)
        #expect(abs(bounds.max.x - 100) < 0.01 && abs(bounds.max.y - 100) < 0.01)
    }
}

/// Unit quad facing +Z, red unlit-free PBR base colour. Quantized: positions SHORT scaled by the
/// node (1/100), normals normalized BYTE, UVs normalized USHORT.
private func quadGLB(quantized: Bool) throws -> Data {
    var bin = Data()
    func append<T: FixedWidthInteger>(_ values: [T]) {
        for value in values {
            var bits = value.littleEndian
            Swift.withUnsafeBytes(of: &bits) { bin.append(contentsOf: $0) }
        }
        while bin.count % 4 != 0 { bin.append(0) }
    }
    var views: [[String: Any]] = []
    func view(_ start: Int) { views.append(["buffer": 0, "byteOffset": start, "byteLength": bin.count - start]) }
    var start = bin.count
    if quantized { append([Int16(0), 0, 0, 100, 0, 0, 100, 100, 0, 0, 100, 0]) } else {
        appendFloats([0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0], to: &bin)
    }
    view(start); start = bin.count
    if quantized { append([Int8](repeating: 0, count: 0) + (0..<4).flatMap { _ in [Int8(0), 0, 127, 0] }) } else {
        appendFloats((0..<4).flatMap { _ in [Float(0), 0, 1] }, to: &bin)
    }
    view(start); start = bin.count
    if quantized { append([UInt16(0), 65535, 65535, 65535, 65535, 0, 0, 0]) } else {
        appendFloats([0, 1, 1, 1, 1, 0, 0, 0], to: &bin)
    }
    view(start); start = bin.count
    append([UInt16(0), 1, 2, 0, 2, 3])
    view(start)
    // Quantized normals are VEC3 in a 4-byte stride (spec: vertex attributes align to 4 bytes).
    if quantized { views[1]["byteStride"] = 4 }
    let json: [String: Any] = [
        "asset": ["version": "2.0"],
        "extensionsUsed": quantized ? ["KHR_mesh_quantization"] : [],
        "extensionsRequired": quantized ? ["KHR_mesh_quantization"] : [],
        "buffers": [["byteLength": bin.count]],
        "bufferViews": views,
        "accessors": [
            quantized
                ? ["bufferView": 0, "componentType": 5122, "count": 4, "type": "VEC3", "min": [0, 0, 0], "max": [100, 100, 0]]
                : ["bufferView": 0, "componentType": 5126, "count": 4, "type": "VEC3", "min": [0, 0, 0], "max": [1, 1, 0]],
            quantized
                ? ["bufferView": 1, "componentType": 5120, "normalized": true, "count": 4, "type": "VEC3"]
                : ["bufferView": 1, "componentType": 5126, "count": 4, "type": "VEC3"],
            quantized
                ? ["bufferView": 2, "componentType": 5123, "normalized": true, "count": 4, "type": "VEC2"]
                : ["bufferView": 2, "componentType": 5126, "count": 4, "type": "VEC2"],
            ["bufferView": 3, "componentType": 5123, "count": 6, "type": "SCALAR"],
        ],
        "materials": [["pbrMetallicRoughness": ["baseColorFactor": [0.8, 0.1, 0.1, 1], "metallicFactor": 0]]],
        "meshes": [["primitives": [["attributes": ["POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2], "indices": 3, "material": 0]]]],
        "nodes": [quantized ? ["mesh": 0, "scale": [0.01, 0.01, 0.01]] : ["mesh": 0]],
        "scenes": [["nodes": [0]]],
        "scene": 0,
    ]
    return try TestGLB.serialize(json: json, bin: bin)
}
