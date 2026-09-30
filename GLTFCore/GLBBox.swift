import Foundation

/// A GLB split into its JSON and BIN chunks — the read side. Writing GLBs (`serialize`,
/// `packSidecar`, `writePrepared`) belongs to the RealityKit prepare path and lives there as an
/// extension (`RendererRealityKit/GLBBox+Write.swift`).
public struct GLBBox {
    private static let magic = Data("glTF".utf8)

    public var json: [String: Any]
    public var bin: Data

    public init(json: [String: Any], bin: Data) {
        self.json = json
        self.bin = bin
    }

    public enum Error: Swift.Error, Equatable {
        case invalidGLB
        case missingBuffer
    }

    public static func aligned(_ value: Int, to align: Int) -> Int {
        (value + align - 1) / align * align
    }

    /// JSON object from a `.gltf` file or a GLB JSON chunk. Strips a UTF-8 BOM —
    /// `JSONSerialization` rejects it; cgltf does not.
    public static func parseJSON(_ data: Data) throws -> [String: Any] {
        var payload = data
        if payload.starts(with: [0xEF, 0xBB, 0xBF]) {
            payload = payload.subdata(in: 3..<payload.count)
        }
        guard let object = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            throw Error.invalidGLB
        }
        return object
    }

    public static func parse(_ data: Data) throws -> GLBBox {
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
    public static func peekJSON(from url: URL) throws -> [String: Any] {
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

    /// JSON object for a `.gltf` sidecar or a GLB JSON chunk. Does not read the BIN.
    public static func peekDocumentJSON(from url: URL) throws -> [String: Any] {
        if url.pathExtension.lowercased() == "gltf" {
            return try parseJSON(Data(contentsOf: url, options: [.mappedIfSafe]))
        }
        return try peekJSON(from: url)
    }

    public static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let n as Int: return n
        case let n as NSNumber: return n.intValue
        default: return nil
        }
    }

    public static func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let n as Double: return n
        case let n as Int: return Double(n)
        case let n as NSNumber: return n.doubleValue
        default: return nil
        }
    }

    public static func doubleArray(_ value: Any?) -> [Double]? {
        (value as? [Any])?.map { doubleValue($0) ?? 0 }
    }

    public static func readUInt16(_ data: Data, _ offset: Int) -> UInt16 {
        var value: UInt16 = 0
        _ = withUnsafeMutableBytes(of: &value) { dest in
            data.copyBytes(to: dest, from: offset..<(offset + 2))
        }
        return UInt16(littleEndian: value)
    }

    public static func readUInt32(_ data: Data, _ offset: Int) -> UInt32 {
        var value: UInt32 = 0
        _ = withUnsafeMutableBytes(of: &value) { dest in
            data.copyBytes(to: dest, from: offset..<(offset + 4))
        }
        return UInt32(littleEndian: value)
    }

    /// Also used by `GLTFBinaryStore` when a sidecar buffer or image is inlined.
    public static func decodeDataURI(_ uri: String) -> Data? {
        guard uri.hasPrefix("data:"), let comma = uri.firstIndex(of: ",") else { return nil }
        let meta = uri[uri.index(uri.startIndex, offsetBy: 5)..<comma]
        let payload = String(uri[uri.index(after: comma)...])
        if meta.lowercased().contains(";base64") {
            return Data(base64Encoded: payload, options: [.ignoreUnknownCharacters])
        }
        return payload.removingPercentEncoding.flatMap { $0.data(using: .utf8) } ?? payload.data(using: .utf8)
    }
}
