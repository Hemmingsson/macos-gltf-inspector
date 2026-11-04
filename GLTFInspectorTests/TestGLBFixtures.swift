import Foundation

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

