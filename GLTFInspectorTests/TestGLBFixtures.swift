import CoreGraphics
import Foundation
import ImageIO

/// GLB bytes for tests, built in the test target: JSON chunk padded with spaces, BIN chunk padded
/// with zeros (what `GLBBox.parse` reads).
enum TestGLB {
    struct InvalidJSON: Error {}

    static func serialize(json: [String: Any], bin: Data) throws -> Data {
        guard JSONSerialization.isValidJSONObject(json) else { throw InvalidJSON() }
        var jsonData = try JSONSerialization.data(withJSONObject: json, options: [])
        jsonData.append(Data(repeating: 0x20, count: pad4(jsonData.count)))
        var binData = bin
        binData.append(Data(count: pad4(binData.count)))

        var out = Data()
        out.append(contentsOf: Array("glTF".utf8))
        out.append(contentsOf: uint32(2))
        out.append(contentsOf: uint32(UInt32(12 + 8 + jsonData.count + 8 + binData.count)))
        out.append(contentsOf: uint32(UInt32(jsonData.count)))
        out.append(contentsOf: Array("JSON".utf8))
        out.append(jsonData)
        out.append(contentsOf: uint32(UInt32(binData.count)))
        out.append(contentsOf: Array("BIN\0".utf8))
        out.append(binData)
        return out
    }

    /// Writes `data` to a fresh temp `.glb`; the caller removes it.
    static func writeTemp(_ data: Data, prefix: String) throws -> URL {
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString).glb")
        try data.write(to: out)
        return out
    }

    /// First buffer from a sidecar `.gltf` JSON with a `data:` URI (e.g. fixture models).
    static func embeddedBin(from json: [String: Any]) throws -> Data {
        guard let buffers = json["buffers"] as? [[String: Any]],
              let uri = buffers[0]["uri"] as? String,
              uri.hasPrefix("data:"),
              let comma = uri.firstIndex(of: ",")
        else { throw InvalidJSON() }
        let payload = String(uri[uri.index(after: comma)...])
        guard let data = Data(base64Encoded: payload, options: [.ignoreUnknownCharacters]) else { throw InvalidJSON() }
        return data
    }

    static func writeTempGLB(json: [String: Any], prefix: String) throws -> URL {
        let bin = try embeddedBin(from: json)
        var glbJSON = json
        if var buffers = glbJSON["buffers"] as? [[String: Any]], !buffers.isEmpty {
            buffers[0]["byteLength"] = bin.count
            buffers[0].removeValue(forKey: "uri")
            glbJSON["buffers"] = buffers
        }
        return try writeTemp(try serialize(json: glbJSON, bin: bin), prefix: prefix)
    }

    private static func pad4(_ count: Int) -> Int { (4 - count % 4) % 4 }

    private static func uint32(_ value: UInt32) -> [UInt8] {
        withUnsafeBytes(of: value.littleEndian) { Array($0) }
    }
}

func tinyPNG() -> Data {
    Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
}

func appendFloats(_ values: [Float], to data: inout Data) {
    for value in values {
        var bits = value.bitPattern.littleEndian
        Swift.withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
    }
}

func floatTrianglePositions() -> [Float] {
    [0, 0, 0, 1, 0, 0, 0, 1, 0]
}

func floatTriangleBin() -> Data {
    var bin = Data()
    appendFloats(floatTrianglePositions(), to: &bin)
    return bin
}

/// Unit square in the XY plane at z = 0, facing +Z, with UVs 0…1.
func floatQuadWithUVBin() -> Data {
    var bin = Data()
    let positions: [Float] = [
        -1, -1, 0, 1, -1, 0, 1, 1, 0, -1, 1, 0,
    ]
    let uvs: [Float] = [0, 0, 1, 0, 1, 1, 0, 1]
    appendFloats(positions, to: &bin)
    appendFloats(uvs, to: &bin)
    let indices: [UInt16] = [0, 1, 2, 0, 2, 3]
    for index in indices {
        var bits = index.littleEndian
        Swift.withUnsafeBytes(of: &bits) { bin.append(contentsOf: $0) }
    }
    return bin
}

/// RGBA PNG; every pixel uses the same alpha (`opaqueCenter` false → center texel alpha 0).
func rgbaPNG(width: Int, height: Int, opaqueCenter: Bool = true) -> Data {
    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    if !opaqueCenter, width > 2, height > 2 {
        let cx = width / 2, cy = height / 2
        let offset = (cy * width + cx) * 4 + 3
        pixels[offset] = 0
    }
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
          let image = context.makeImage(),
          let dest = CFDataCreateMutable(nil, 0),
          let png = CGImageDestinationCreateWithData(dest, "public.png" as CFString, 1, nil)
    else { return tinyPNG() }
    CGImageDestinationAddImage(png, image, nil)
    guard CGImageDestinationFinalize(png), let data = dest as Data? else { return tinyPNG() }
    return data
}

/// Two quads stacked on Z: node 0 at z = -1 (back), node 1 at z = 0 (front).
func writeTempStackedQuadsGLB(prefix: String = "stacked-quads") throws -> URL {
    let bin = floatQuadWithUVBin()
    let json: [String: Any] = [
        "asset": ["version": "2.0"],
        "buffers": [["byteLength": bin.count]],
        "bufferViews": [
            ["buffer": 0, "byteOffset": 0, "byteLength": 48],
            ["buffer": 0, "byteOffset": 48, "byteLength": 32],
            ["buffer": 0, "byteOffset": 80, "byteLength": 12],
        ],
        "accessors": [
            ["bufferView": 0, "componentType": 5126, "count": 4, "type": "VEC3",
             "min": [-1, -1, 0], "max": [1, 1, 0]],
            ["bufferView": 1, "componentType": 5126, "count": 4, "type": "VEC2"],
            ["bufferView": 2, "componentType": 5123, "count": 6, "type": "SCALAR"],
        ],
        "meshes": [["primitives": [[
            "attributes": ["POSITION": 0, "TEXCOORD_0": 1],
            "indices": 2,
        ]]]],
        "nodes": [
            ["name": "Back", "mesh": 0, "translation": [0, 0, -1]],
            ["name": "Front", "mesh": 0],
        ],
        "scenes": [["nodes": [0, 1]]],
        "scene": 0,
    ]
    return try TestGLB.writeTemp(try TestGLB.serialize(json: json, bin: bin), prefix: prefix)
}

/// Empty parent (node 0) with one translated mesh child (node 1).
func writeTempGroupedMeshGLB(prefix: String = "grouped-mesh") throws -> URL {
    let bin = floatQuadWithUVBin()
    let json: [String: Any] = [
        "asset": ["version": "2.0"],
        "buffers": [["byteLength": bin.count]],
        "bufferViews": [
            ["buffer": 0, "byteOffset": 0, "byteLength": 48],
            ["buffer": 0, "byteOffset": 48, "byteLength": 32],
            ["buffer": 0, "byteOffset": 80, "byteLength": 12],
        ],
        "accessors": [
            ["bufferView": 0, "componentType": 5126, "count": 4, "type": "VEC3",
             "min": [-1, -1, 0], "max": [1, 1, 0]],
            ["bufferView": 1, "componentType": 5126, "count": 4, "type": "VEC2"],
            ["bufferView": 2, "componentType": 5123, "count": 6, "type": "SCALAR"],
        ],
        "meshes": [["primitives": [[
            "attributes": ["POSITION": 0, "TEXCOORD_0": 1],
            "indices": 2,
        ]]]],
        "nodes": [
            ["name": "Group", "children": [1]],
            ["name": "Mesh", "mesh": 0, "translation": [0.5, 0, 0]],
        ],
        "scenes": [["nodes": [0]]],
        "scene": 0,
    ]
    return try TestGLB.writeTemp(try TestGLB.serialize(json: json, bin: bin), prefix: prefix)
}

/// Root → group → mesh; mesh translated on X (default +10).
func writeTempNestedGroupedMeshGLB(
    meshTranslation: [Float] = [10, 0, 0],
    prefix: String = "nested-group-mesh"
) throws -> URL {
    let bin = floatQuadWithUVBin()
    let json: [String: Any] = [
        "asset": ["version": "2.0"],
        "buffers": [["byteLength": bin.count]],
        "bufferViews": [
            ["buffer": 0, "byteOffset": 0, "byteLength": 48],
            ["buffer": 0, "byteOffset": 48, "byteLength": 32],
            ["buffer": 0, "byteOffset": 80, "byteLength": 12],
        ],
        "accessors": [
            ["bufferView": 0, "componentType": 5126, "count": 4, "type": "VEC3",
             "min": [-1, -1, 0], "max": [1, 1, 0]],
            ["bufferView": 1, "componentType": 5126, "count": 4, "type": "VEC2"],
            ["bufferView": 2, "componentType": 5123, "count": 6, "type": "SCALAR"],
        ],
        "meshes": [["primitives": [[
            "attributes": ["POSITION": 0, "TEXCOORD_0": 1],
            "indices": 2,
        ]]]],
        "nodes": [
            ["name": "Root", "children": [1]],
            ["name": "Group", "children": [2]],
            ["name": "Mesh", "mesh": 0, "translation": meshTranslation],
        ],
        "scenes": [["nodes": [0]]],
        "scene": 0,
    ]
    return try TestGLB.writeTemp(try TestGLB.serialize(json: json, bin: bin), prefix: prefix)
}

/// MASK quad in front of an opaque quad; texture center is transparent.
func writeTempMaskOverOpaqueGLB(prefix: String = "mask-over-opaque") throws -> URL {
    let meshBin = floatQuadWithUVBin()
    let png = rgbaPNG(width: 5, height: 5, opaqueCenter: false)
    var bin = meshBin
    bin.append(png)
    let pngOffset = meshBin.count
    let json: [String: Any] = [
        "asset": ["version": "2.0"],
        "buffers": [["byteLength": bin.count]],
        "bufferViews": [
            ["buffer": 0, "byteOffset": 0, "byteLength": 48],
            ["buffer": 0, "byteOffset": 48, "byteLength": 32],
            ["buffer": 0, "byteOffset": 80, "byteLength": 12],
            ["buffer": 0, "byteOffset": pngOffset, "byteLength": png.count],
        ],
        "accessors": [
            ["bufferView": 0, "componentType": 5126, "count": 4, "type": "VEC3",
             "min": [-1, -1, 0], "max": [1, 1, 0]],
            ["bufferView": 1, "componentType": 5126, "count": 4, "type": "VEC2"],
            ["bufferView": 2, "componentType": 5123, "count": 6, "type": "SCALAR"],
        ],
        "images": [["mimeType": "image/png", "bufferView": 3]],
        "textures": [["source": 0]],
        "materials": [
            ["name": "Opaque", "pbrMetallicRoughness": ["baseColorFactor": [1, 1, 1, 1]]],
            ["name": "Mask", "alphaMode": "MASK", "alphaCutoff": 0.5,
             "pbrMetallicRoughness": ["baseColorTexture": ["index": 0]]],
        ],
        "meshes": [
            ["primitives": [["attributes": ["POSITION": 0, "TEXCOORD_0": 1], "indices": 2, "material": 0]]],
            ["primitives": [["attributes": ["POSITION": 0, "TEXCOORD_0": 1], "indices": 2, "material": 1]]],
        ],
        "nodes": [
            ["name": "Back", "mesh": 0, "translation": [0, 0, -1]],
            ["name": "MaskFront", "mesh": 1],
        ],
        "scenes": [["nodes": [0, 1]]],
        "scene": 0,
    ]
    return try TestGLB.writeTemp(try TestGLB.serialize(json: json, bin: bin), prefix: prefix)
}

/// Centered quad (node 0) and a perspective camera on node 1 at z = 3.
func writeTempCameraPickGLB(prefix: String = "camera-pick") throws -> URL {
    let bin = floatQuadWithUVBin()
    let json: [String: Any] = [
        "asset": ["version": "2.0"],
        "buffers": [["byteLength": bin.count]],
        "bufferViews": [
            ["buffer": 0, "byteOffset": 0, "byteLength": 48],
            ["buffer": 0, "byteOffset": 48, "byteLength": 32],
            ["buffer": 0, "byteOffset": 80, "byteLength": 12],
        ],
        "accessors": [
            ["bufferView": 0, "componentType": 5126, "count": 4, "type": "VEC3",
             "min": [-1, -1, 0], "max": [1, 1, 0]],
            ["bufferView": 1, "componentType": 5126, "count": 4, "type": "VEC2"],
            ["bufferView": 2, "componentType": 5123, "count": 6, "type": "SCALAR"],
        ],
        "cameras": [["type": "perspective", "perspective": ["yfov": 1.0, "znear": 0.1, "zfar": 100]]],
        "meshes": [["primitives": [["attributes": ["POSITION": 0, "TEXCOORD_0": 1], "indices": 2]]]],
        "nodes": [
            ["name": "Mesh", "mesh": 0],
            ["name": "Cam", "camera": 0, "translation": [0, 0, 3]],
        ],
        "scenes": [["nodes": [0, 1]]],
        "scene": 0,
    ]
    return try TestGLB.writeTemp(try TestGLB.serialize(json: json, bin: bin), prefix: prefix)
}

func writeTempOneNodeMeshGLB(nodeName: String, prefix: String = "one-node") throws -> URL {
    let bin = floatTriangleBin()
    let json: [String: Any] = [
        "asset": ["version": "2.0"],
        "buffers": [["byteLength": bin.count]],
        "bufferViews": [["buffer": 0, "byteOffset": 0, "byteLength": bin.count]],
        "accessors": [[
            "bufferView": 0,
            "componentType": 5126,
            "count": 3,
            "type": "VEC3",
        ]],
        "meshes": [["name": "HelmetMesh", "primitives": [["attributes": ["POSITION": 0]]]]],
        "nodes": [["name": nodeName, "mesh": 0]],
        "scenes": [["name": "Default", "nodes": [0]]],
        "scene": 0,
    ]
    return try TestGLB.writeTemp(try TestGLB.serialize(json: json, bin: bin), prefix: prefix)
}

/// Hip → non-joint pivot → knee; skin lists hip and knee only (bone must skip the pivot).
func writeTempSkinWithPivotGLB(prefix: String = "skin-pivot") throws -> URL {
    let positions = floatTrianglePositions()
    var joints = Data()
    for _ in 0..<3 {
        for _ in 0..<4 {
            var bits = UInt16(0).littleEndian
            Swift.withUnsafeBytes(of: &bits) { joints.append(contentsOf: $0) }
        }
    }
    var weights = Data()
    appendFloats([1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0], to: &weights)
    let identity: [Float] = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
    var ibm = Data()
    appendFloats(identity + identity, to: &ibm)
    var bin = Data()
    appendFloats(positions, to: &bin)
    bin.append(joints)
    bin.append(weights)
    bin.append(ibm)
    let p = positions.count * MemoryLayout<Float>.size
    let j = joints.count
    let w = weights.count
    let json: [String: Any] = [
        "asset": ["version": "2.0"],
        "buffers": [["byteLength": bin.count]],
        "bufferViews": [
            ["buffer": 0, "byteOffset": 0, "byteLength": p],
            ["buffer": 0, "byteOffset": p, "byteLength": j],
            ["buffer": 0, "byteOffset": p + j, "byteLength": w],
            ["buffer": 0, "byteOffset": p + j + w, "byteLength": ibm.count],
        ],
        "accessors": [
            ["bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3",
             "max": [1, 1, 0], "min": [0, 0, 0]],
            ["bufferView": 1, "componentType": 5123, "count": 3, "type": "VEC4"],
            ["bufferView": 2, "componentType": 5126, "count": 3, "type": "VEC4"],
            ["bufferView": 3, "componentType": 5126, "count": 2, "type": "MAT4"],
        ],
        "meshes": [["primitives": [["attributes": ["POSITION": 0, "JOINTS_0": 1, "WEIGHTS_0": 2]]]]],
        "skins": [["name": "Leg", "joints": [1, 3], "inverseBindMatrices": 3]],
        "nodes": [
            ["name": "Mesh", "mesh": 0, "skin": 0, "children": [1]],
            ["name": "Hip", "children": [2]],
            ["name": "Pivot", "children": [3], "translation": [0, 0.5, 0]],
            ["name": "Knee", "translation": [0, 0.5, 0]],
        ],
        "scenes": [["nodes": [0]]],
        "scene": 0,
    ]
    return try TestGLB.writeTemp(try TestGLB.serialize(json: json, bin: bin), prefix: prefix)
}

