import Foundation

/// Lazy, memoized access to a glTF file's binary payload for JSON-only parsing.
///
/// Nothing is read until a caller actually needs bytes — image thumbs, or an animation
/// input accessor that omits `min`/`max` — and each buffer is resolved at most once.
/// Handles all three glTF payload shapes: the GLB `BIN` chunk, `data:` URIs, and
/// sidecar files next to the `.gltf`.
final class GLTFBinaryStore {
    private let json: [String: Any]
    private let fileURL: URL?
    private var buffers: [Int: Data?] = [:]
    private var glbChunk: Data??

    init(json: [String: Any], fileURL: URL?) {
        self.json = json
        self.fileURL = fileURL
    }

    /// Empty store for callers that only have JSON (unit tests, sidecars we cannot reach).
    static let unavailable = GLTFBinaryStore(json: [:], fileURL: nil)

    // MARK: - Accessors

    /// Float `SCALAR` accessor values — animation sampler inputs whose `min`/`max` are missing.
    /// Sparse accessors are not resolved; they never carry keyframe times in practice.
    func scalarFloats(accessor: [String: Any]) -> [Float]? {
        guard GLTFJSON.int(accessor["componentType"]) == 5126,
              (accessor["type"] as? String) == "SCALAR",
              let count = GLTFJSON.int(accessor["count"]), count > 0,
              let viewIndex = GLTFJSON.int(accessor["bufferView"]),
              let bytes = bufferViewBytes(viewIndex)
        else { return nil }
        let stride = bufferViewStride(viewIndex) ?? 4
        let base = GLTFJSON.int(accessor["byteOffset"]) ?? 0
        var values: [Float] = []
        values.reserveCapacity(count)
        for index in 0..<count {
            let offset = base + index * stride
            guard offset >= 0, offset + 4 <= bytes.count else { break }
            values.append(Float(bitPattern: GLBBox.readUInt32(bytes, offset)))
        }
        return values.isEmpty ? nil : values
    }

    /// Encoded bytes for one `images[…]` entry (`bufferView` or `uri`).
    func imageBytes(_ image: [String: Any]) -> Data? {
        if let viewIndex = GLTFJSON.int(image["bufferView"]) {
            return bufferViewBytes(viewIndex)
        }
        guard let uri = image["uri"] as? String, !uri.isEmpty else { return nil }
        return bytes(forURI: uri)
    }

    // MARK: - Buffers

    func bufferViewBytes(_ index: Int) -> Data? {
        let views = json["bufferViews"] as? [[String: Any]] ?? []
        guard views.indices.contains(index) else { return nil }
        let view = views[index]
        guard let data = buffer(GLTFJSON.int(view["buffer"]) ?? 0) else { return nil }
        let offset = GLTFJSON.int(view["byteOffset"]) ?? 0
        let length = GLTFJSON.int(view["byteLength"]) ?? 0
        guard offset >= 0, length > 0, offset + length <= data.count else { return nil }
        return data.subdata(in: offset..<(offset + length))
    }

    private func bufferViewStride(_ index: Int) -> Int? {
        let views = json["bufferViews"] as? [[String: Any]] ?? []
        guard views.indices.contains(index) else { return nil }
        guard let stride = GLTFJSON.int(views[index]["byteStride"]), stride > 0 else { return nil }
        return stride
    }

    private func buffer(_ index: Int) -> Data? {
        if let cached = buffers[index] { return cached }
        let resolved = loadBuffer(index)
        buffers[index] = resolved
        return resolved
    }

    private func loadBuffer(_ index: Int) -> Data? {
        let declared = json["buffers"] as? [[String: Any]] ?? []
        guard declared.indices.contains(index) else { return nil }
        if let uri = declared[index]["uri"] as? String, !uri.isEmpty {
            return bytes(forURI: uri)
        }
        // No URI: the payload is the GLB BIN chunk, which only buffer 0 may claim.
        return index == 0 ? binChunk() : nil
    }

    private func bytes(forURI uri: String) -> Data? {
        if uri.hasPrefix("data:") {
            return GLBBox.decodeDataURI(uri)
        }
        guard let fileURL else { return nil }
        let decoded = uri.removingPercentEncoding ?? uri
        let sidecar = fileURL.deletingLastPathComponent().appendingPathComponent(decoded)
        return try? Data(contentsOf: sidecar, options: [.mappedIfSafe])
    }

    private func binChunk() -> Data? {
        if let cached = glbChunk { return cached }
        let resolved: Data? = {
            guard let fileURL, fileURL.pathExtension.lowercased() == "glb",
                  let data = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]),
                  let box = try? GLBBox.parse(data), !box.bin.isEmpty
            else { return nil }
            return box.bin
        }()
        glbChunk = resolved
        return resolved
    }
}
