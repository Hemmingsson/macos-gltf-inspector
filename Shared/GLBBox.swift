import Foundation

struct GLBBox {
    private static let magic = Data("glTF".utf8)

    var json: [String: Any]
    var bin: Data

    enum Error: Swift.Error, Equatable {
        case invalidGLB
        case missingBuffer
    }

    static func aligned(_ value: Int, to align: Int) -> Int {
        (value + align - 1) / align * align
    }

    /// JSON object from a `.gltf` file or a GLB JSON chunk. Strips a UTF-8 BOM —
    /// `JSONSerialization` rejects it; cgltf does not.
    static func parseJSON(_ data: Data) throws -> [String: Any] {
        var payload = data
        if payload.starts(with: [0xEF, 0xBB, 0xBF]) {
            payload = payload.subdata(in: 3..<payload.count)
        }
        guard let object = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            throw Error.invalidGLB
        }
        return object
    }

    static func parse(_ data: Data) throws -> GLBBox {
        guard data.count >= 12, data.prefix(4) == magic else { throw Error.invalidGLB }
        var offset = 12
        var json: [String: Any] = [:]
        var bin = Data()
        while offset + 8 <= data.count {
            let chunkLen = Int(readUInt32(data, offset))
            let type = String(data: data.subdata(in: (offset + 4)..<(offset + 8)), encoding: .ascii) ?? ""
            let start = offset + 8
            let end = start + chunkLen
            guard end <= data.count else { throw Error.invalidGLB }
            let payload = data.subdata(in: start..<end)
            if type.hasPrefix("JSON") {
                json = try parseJSON(payload)
            } else if type.hasPrefix("BIN") {
                bin = payload
            }
            offset = aligned(end, to: 4)
        }
        return GLBBox(json: json, bin: bin)
    }

    /// JSON chunk only — skips the BIN so prepares can bail without copying textures.
    static func peekJSON(from url: URL) throws -> [String: Any] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard let header = try handle.read(upToCount: 12), header.count == 12, header.prefix(4) == magic,
              let chunkHeader = try handle.read(upToCount: 8), chunkHeader.count == 8
        else {
            throw Error.invalidGLB
        }
        let chunkLen = Int(readUInt32(chunkHeader, 0))
        let type = String(data: chunkHeader.subdata(in: 4..<8), encoding: .ascii) ?? ""
        guard type.hasPrefix("JSON"),
              let payload = try handle.read(upToCount: chunkLen), payload.count == chunkLen
        else {
            throw Error.invalidGLB
        }
        return try parseJSON(payload)
    }

    /// Packs a sidecar `.gltf` (JSON + external/data-URI buffers and images) into a GLB
    /// so peek/prepare can run on one file. This is the usual workaround: glTF JSON is
    /// not a GLB JSON chunk (`glTF` magic + BIN), so `peekJSON`/`parse` reject it.
    static func packSidecar(
        _ json: [String: Any],
        readURI: (String) throws -> Data
    ) throws -> Data {
        var json = json
        var bin = Data()
        var bases: [Int] = []
        let buffers = json["buffers"] as? [[String: Any]] ?? []
        for buffer in buffers {
            let bytes = try payload(for: buffer, readURI: readURI)
            let start = aligned(bin.count, to: 4)
            if start > bin.count {
                bin.append(Data(count: start - bin.count))
            }
            bases.append(start)
            bin.append(bytes)
        }
        var bufferViews = json["bufferViews"] as? [[String: Any]] ?? []
        for i in bufferViews.indices {
            let bufferIndex = intValue(bufferViews[i]["buffer"]) ?? 0
            guard bases.indices.contains(bufferIndex) else { continue }
            let offset = intValue(bufferViews[i]["byteOffset"]) ?? 0
            bufferViews[i]["buffer"] = 0
            bufferViews[i]["byteOffset"] = bases[bufferIndex] + offset
        }
        if var images = json["images"] as? [[String: Any]] {
            for i in images.indices {
                guard let uri = images[i]["uri"] as? String, !uri.isEmpty else { continue }
                let bytes: Data
                do {
                    bytes = try payload(uri: uri, readURI: readURI)
                } catch {
                    continue
                }
                let view = appendBytes(bytes, bin: &bin, bufferViews: &bufferViews)
                images[i]["bufferView"] = view
                images[i].removeValue(forKey: "uri")
                if images[i]["mimeType"] == nil, let mime = mimeType(forImageURI: uri) {
                    images[i]["mimeType"] = mime
                }
            }
            json["images"] = images
        }
        json["bufferViews"] = bufferViews
        json["buffers"] = [["byteLength": bin.count]]
        return try serialize(json: json, bin: bin)
    }

    static func rewriteExtensionLists(
        _ json: inout [String: Any],
        removing: Set<String>,
        addingToUsed: [String] = []
    ) {
        func rewrite(_ key: String, adding: [String]) {
            var list = (json[key] as? [String]) ?? []
            list.removeAll { removing.contains($0) }
            for name in adding where !list.contains(name) {
                list.append(name)
            }
            if list.isEmpty {
                json.removeValue(forKey: key)
            } else {
                json[key] = list
            }
        }
        rewrite("extensionsUsed", adding: addingToUsed)
        rewrite("extensionsRequired", adding: [])
    }

    static func writePrepared(_ data: Data, prefix: String) throws -> URL {
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString).glb")
        try data.write(to: out)
        return out
    }

    static func serialize(json: [String: Any], bin: Data) throws -> Data {
        // Invalid numbers (NaN/Inf from a bad prepare) throw NSException, not Error.
        var jsonData: Data?
        var serializationError: Swift.Error?
        try GLBTry.run {
            do {
                jsonData = try JSONSerialization.data(withJSONObject: json, options: [])
            } catch {
                serializationError = error
            }
        }
        if let serializationError { throw serializationError }
        guard var jsonData else { throw Error.invalidGLB }
        jsonData.append(Data(repeating: 0x20, count: pad4(jsonData.count)))
        var binData = bin
        binData.append(Data(count: pad4(binData.count)))

        var out = Data()
        out.append(contentsOf: Array("glTF".utf8))
        out.append(contentsOf: uint32(2))
        let total = 12 + 8 + jsonData.count + 8 + binData.count
        out.append(contentsOf: uint32(UInt32(total)))
        out.append(contentsOf: uint32(UInt32(jsonData.count)))
        out.append(contentsOf: Array("JSON".utf8))
        out.append(jsonData)
        out.append(contentsOf: uint32(UInt32(binData.count)))
        out.append(contentsOf: Array("BIN\0".utf8))
        out.append(binData)
        return out
    }

    static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let n as Int: return n
        case let n as NSNumber: return n.intValue
        default: return nil
        }
    }

    static func appendBytes(_ bytes: Data, bin: inout Data, bufferViews: inout [[String: Any]]) -> Int {
        let offset = aligned(bin.count, to: 4)
        if offset > bin.count {
            bin.append(Data(count: offset - bin.count))
        }
        bin.append(bytes)
        bufferViews.append([
            "buffer": 0,
            "byteOffset": offset,
            "byteLength": bytes.count,
        ])
        return bufferViews.count - 1
    }

    static func setPrimaryBufferLength(_ json: inout [String: Any], _ byteLength: Int) {
        guard var buffers = json["buffers"] as? [[String: Any]], !buffers.isEmpty else { return }
        buffers[0]["byteLength"] = byteLength
        json["buffers"] = buffers
    }

    static func readUInt16(_ data: Data, _ offset: Int) -> UInt16 {
        var value: UInt16 = 0
        _ = withUnsafeMutableBytes(of: &value) { dest in
            data.copyBytes(to: dest, from: offset..<(offset + 2))
        }
        return UInt16(littleEndian: value)
    }

    static func readUInt32(_ data: Data, _ offset: Int) -> UInt32 {
        var value: UInt32 = 0
        _ = withUnsafeMutableBytes(of: &value) { dest in
            data.copyBytes(to: dest, from: offset..<(offset + 4))
        }
        return UInt32(littleEndian: value)
    }

    private static func payload(for buffer: [String: Any], readURI: (String) throws -> Data) throws -> Data {
        if let uri = buffer["uri"] as? String, !uri.isEmpty {
            return try payload(uri: uri, readURI: readURI)
        }
        let length = intValue(buffer["byteLength"]) ?? 0
        guard length == 0 else { throw Error.missingBuffer }
        return Data()
    }

    private static func payload(uri: String, readURI: (String) throws -> Data) throws -> Data {
        if uri.hasPrefix("data:") {
            guard let data = decodeDataURI(uri) else { throw Error.missingBuffer }
            return data
        }
        return try readURI(uri)
    }

    private static func decodeDataURI(_ uri: String) -> Data? {
        guard uri.hasPrefix("data:"), let comma = uri.firstIndex(of: ",") else { return nil }
        let meta = uri[uri.index(uri.startIndex, offsetBy: 5)..<comma]
        let payload = String(uri[uri.index(after: comma)...])
        if meta.lowercased().contains(";base64") {
            return Data(base64Encoded: payload, options: [.ignoreUnknownCharacters])
        }
        return payload.removingPercentEncoding.flatMap { $0.data(using: .utf8) } ?? payload.data(using: .utf8)
    }

    private static func mimeType(forImageURI uri: String) -> String? {
        if uri.hasPrefix("data:") {
            let meta = uri.prefix(while: { $0 != "," }).lowercased()
            if meta.contains("image/png") { return "image/png" }
            if meta.contains("image/jpeg") || meta.contains("image/jpg") { return "image/jpeg" }
            if meta.contains("image/webp") { return "image/webp" }
            return nil
        }
        switch URL(fileURLWithPath: uri).pathExtension.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "webp": return "image/webp"
        default: return nil
        }
    }

    private static func uint32(_ value: UInt32) -> [UInt8] {
        withUnsafeBytes(of: value.littleEndian, Array.init)
    }

    private static func pad4(_ count: Int) -> Int {
        (4 - (count % 4)) % 4
    }
}
