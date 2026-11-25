import Foundation

/// A GLB split into its JSON and BIN chunks. Read-only: nothing rewrites the file.
public struct GLBBox {
    private static let magic = Data("glTF".utf8)

    public var json: [String: Any]
    public var bin: Data

    public enum Error: Swift.Error, LocalizedError, Equatable {
        case invalidGLB
        case unsupportedVersion
        case invalidLength
        case invalidChunk
        case missingJSON

        public var errorDescription: String? {
            "The file isn't a valid glTF binary. It may be damaged or truncated."
        }
    }

    /// JSON object from a `.gltf` file or a GLB JSON chunk. Strips a UTF-8 BOM —
    /// `JSONSerialization` rejects it; cgltf does not.
    public static func parseJSON(_ data: Data) throws -> [String: Any] {
        guard data.count <= GLTFResourceLimits.maxJSONBytes else {
            throw GLTFResourceError.tooLarge(limit: GLTFResourceLimits.maxJSONBytes)
        }
        var payload = data
        if payload.starts(with: [0xEF, 0xBB, 0xBF]) {
            payload = payload[3...]
        }
        guard let object = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            throw Error.invalidGLB
        }
        return object
    }

    public static func parse(_ data: Data) throws -> GLBBox {
        guard data.count <= GLTFResourceLimits.maxSourceBytes else {
            throw GLTFResourceError.tooLarge(limit: GLTFResourceLimits.maxSourceBytes)
        }
        guard data.count >= 12, data.prefix(4) == magic else { throw Error.invalidGLB }
        guard readUInt32(data, 4) == 2 else { throw Error.unsupportedVersion }
        guard Int(readUInt32(data, 8)) == data.count else { throw Error.invalidLength }
        var offset = 12
        var json: [String: Any]?
        var bin = Data()
        var binSeen = false
        while offset < data.count {
            guard data.count - offset >= 8 else { throw Error.invalidChunk }
            let chunkLen = Int(readUInt32(data, offset))
            let type = String(data: data.subdata(in: (offset + 4)..<(offset + 8)), encoding: .ascii) ?? ""
            let start = offset + 8
            guard chunkLen % 4 == 0, chunkLen <= data.count - start else { throw Error.invalidChunk }
            let end = start + chunkLen
            let payload = data.subdata(in: start..<end)
            if type == "JSON" {
                guard json == nil, offset == 12 else { throw Error.invalidChunk }
                json = try parseJSON(payload)
            } else if type == "BIN\0" {
                guard json != nil, !binSeen else { throw Error.invalidChunk }
                binSeen = true
                bin = payload
            } else {
                throw Error.invalidChunk
            }
            offset = end
        }
        guard let json else { throw Error.missingJSON }
        return GLBBox(json: json, bin: bin)
    }

    /// JSON chunk only — never reads the BIN, so textures are not copied.
    static func peekJSON(from url: URL) throws -> [String: Any] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let fileSize = try GLTFResourceIO.fileSize(url)
        guard fileSize <= GLTFResourceLimits.maxSourceBytes else {
            throw GLTFResourceError.tooLarge(limit: GLTFResourceLimits.maxSourceBytes)
        }
        guard let header = try handle.read(upToCount: 12), header.count == 12,
              header.prefix(4) == magic
        else { throw Error.invalidGLB }
        guard readUInt32(header, 4) == 2 else { throw Error.unsupportedVersion }
        guard Int(readUInt32(header, 8)) == fileSize else { throw Error.invalidLength }

        var offset = 12
        var json: [String: Any]?
        var binSeen = false
        while offset < fileSize {
            guard fileSize - offset >= 8,
                  let chunkHeader = try handle.read(upToCount: 8),
                  chunkHeader.count == 8
            else { throw Error.invalidChunk }
            let chunkLen = Int(readUInt32(chunkHeader, 0))
            let type = String(data: chunkHeader.subdata(in: 4..<8), encoding: .ascii) ?? ""
            guard chunkLen % 4 == 0, chunkLen <= fileSize - offset - 8 else {
                throw Error.invalidChunk
            }
            if type == "JSON" {
                guard json == nil, offset == 12 else { throw Error.invalidChunk }
                guard let payload = try handle.read(upToCount: chunkLen), payload.count == chunkLen else {
                    throw Error.invalidChunk
                }
                json = try parseJSON(payload)
            } else if type == "BIN\0" {
                guard json != nil, !binSeen else { throw Error.invalidChunk }
                binSeen = true
                try handle.seek(toOffset: handle.offsetInFile + UInt64(chunkLen))
            } else {
                throw Error.invalidChunk
            }
            offset += 8 + chunkLen
        }
        guard let json else { throw Error.missingJSON }
        return json
    }

    /// JSON object for a `.gltf` sidecar or a GLB JSON chunk. Does not read the BIN.
    public static func peekDocumentJSON(from url: URL) throws -> [String: Any] {
        if url.pathExtension.lowercased() == "gltf" {
            return try parseJSON(GLTFResourceIO.read(url, limit: GLTFResourceLimits.maxSourceBytes))
        }
        return try peekJSON(from: url)
    }

    static func readUInt32(_ data: Data, _ offset: Int) -> UInt32 {
        data.withUnsafeBytes { raw in
            UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
        }
    }

    /// Also used by `GLTFBinaryStore` when a sidecar buffer or image is inlined.
    static func decodeDataURI(_ uri: String) -> Data? {
        guard uri.hasPrefix("data:"), let comma = uri.firstIndex(of: ",") else { return nil }
        let meta = uri[uri.index(uri.startIndex, offsetBy: 5)..<comma]
        let payload = String(uri[uri.index(after: comma)...])
        if meta.lowercased().contains(";base64") {
            return Data(base64Encoded: payload)
        }
        guard let decoded = payload.removingPercentEncoding else { return nil }
        return decoded.data(using: .utf8)
    }
}
