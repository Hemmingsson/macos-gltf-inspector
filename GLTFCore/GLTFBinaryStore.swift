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
        let lastIndex = count - 1
        let lastStride = lastIndex.multipliedReportingOverflow(by: stride)
        let lastOffset = base.addingReportingOverflow(lastStride.partialValue)
        let end = lastOffset.partialValue.addingReportingOverflow(4)
        guard base >= 0, !lastStride.overflow, !lastOffset.overflow, !end.overflow, end.partialValue <= bytes.count else {
            return nil
        }
        var values: [Float] = []
        values.reserveCapacity(count)
        for index in 0..<count {
            let strideOffset = index.multipliedReportingOverflow(by: stride)
            let offset = base.addingReportingOverflow(strideOffset.partialValue)
            guard !strideOffset.overflow, !offset.overflow else { return nil }
            values.append(Float(bitPattern: GLBBox.readUInt32(bytes, offset.partialValue)))
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
        let end = offset.addingReportingOverflow(length)
        guard offset >= 0, length > 0, !end.overflow, end.partialValue <= data.count
        else { return nil }
        return data.subdata(in: offset..<end.partialValue)
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
        guard let byteLength = GLTFJSON.int(declared[index]["byteLength"]), byteLength >= 0,
              byteLength <= GLTFResourceLimits.maxBufferBytes
        else { return nil }
        let data: Data?
        if let uri = declared[index]["uri"] as? String, !uri.isEmpty {
            data = bytes(forURI: uri, limit: GLTFResourceLimits.maxBufferBytes)
        } else {
            // No URI: the payload is the GLB BIN chunk, which only buffer 0 may claim.
            data = index == 0 ? binChunk() : nil
        }
        guard let data, data.count >= byteLength else { return nil }
        return Data(data.prefix(byteLength))
    }

    private func bytes(forURI uri: String, limit: Int = GLTFResourceLimits.maxImageBytes) -> Data? {
        if uri.hasPrefix("data:") {
            guard let data = GLBBox.decodeDataURI(uri), data.count <= min(limit, GLTFResourceLimits.maxDataURIBytes)
            else { return nil }
            return data
        }
        guard let sidecar = resolvedSidecar(uri) else { return nil }
        do {
            return try GLTFResourceIO.read(sidecar, limit: limit)
        } catch {
            AppLog.error(AppLog.app, "referenced resource could not be read: \(error.localizedDescription)")
            return nil
        }
    }

    private func binChunk() -> Data? {
        if let cached = glbChunk { return cached }
        let resolved: Data? = {
            guard let fileURL, fileURL.pathExtension.lowercased() == "glb" else { return nil }
            do {
                let data = try GLTFResourceIO.read(fileURL, limit: GLTFResourceLimits.maxSourceBytes)
                return try GLBBox.parse(data).bin
            } catch {
                AppLog.error(AppLog.app, "GLB binary payload could not be read: \(error.localizedDescription)")
                return nil
            }
        }()
        glbChunk = resolved
        return resolved
    }

    func validateResources() throws {
        let declared = json["buffers"] as? [[String: Any]] ?? []
        for index in declared.indices {
            guard buffer(index) != nil else {
                throw GLTFDocumentJSON.Error.invalidResource("Buffer \(index) is missing or does not match its declared byte length.")
            }
        }

        let views = json["bufferViews"] as? [[String: Any]] ?? []
        for (index, view) in views.enumerated() {
            guard let bufferIndex = GLTFJSON.int(view["buffer"]),
                  declared.indices.contains(bufferIndex),
                  let length = GLTFJSON.int(view["byteLength"]),
                  let data = buffer(bufferIndex)
            else {
                throw GLTFDocumentJSON.Error.invalidResource("Buffer view \(index) is outside its buffer.")
            }
            let offset = GLTFJSON.int(view["byteOffset"]) ?? 0
            let end = offset.addingReportingOverflow(length)
            guard offset >= 0, length > 0, !end.overflow, end.partialValue <= data.count else {
                throw GLTFDocumentJSON.Error.invalidResource("Buffer view \(index) is outside its buffer.")
            }
            if let stride = GLTFJSON.int(view["byteStride"]),
               stride < 4 || stride % 4 != 0 {
                throw GLTFDocumentJSON.Error.invalidResource("Buffer view \(index) has an invalid byte stride.")
            }
        }

        let accessors = json["accessors"] as? [[String: Any]] ?? []
        for (index, accessor) in accessors.enumerated() {
            guard let count = GLTFJSON.int(accessor["count"]), count >= 0 else {
                throw GLTFDocumentJSON.Error.invalidNumeric("Accessor \(index) has an invalid count.")
            }
            guard count <= GLTFResourceLimits.maxAccessorElements else {
                throw GLTFDocumentJSON.Error.invalidNumeric("Accessor \(index) has too many elements.")
            }
            guard let viewIndex = GLTFJSON.int(accessor["bufferView"]) else { continue }
            guard views.indices.contains(viewIndex),
                  let viewData = bufferViewBytes(viewIndex),
                  let elementSize = elementSize(accessor)
            else {
                throw GLTFDocumentJSON.Error.invalidResource("Accessor \(index) is outside its buffer view.")
            }
            let stride = bufferViewStride(viewIndex) ?? elementSize
            let byteOffset = GLTFJSON.int(accessor["byteOffset"]) ?? 0
            guard stride >= elementSize, byteOffset >= 0 else {
                throw GLTFDocumentJSON.Error.invalidResource("Accessor \(index) is outside its buffer view.")
            }
            if count > 0 {
                let lastStride = (count - 1).multipliedReportingOverflow(by: stride)
                let lastOffset = byteOffset.addingReportingOverflow(lastStride.partialValue)
                let end = lastOffset.partialValue.addingReportingOverflow(elementSize)
                guard !lastStride.overflow, !lastOffset.overflow, !end.overflow,
                      end.partialValue <= viewData.count
                else {
                    throw GLTFDocumentJSON.Error.invalidResource("Accessor \(index) is outside its buffer view.")
                }
            }
        }

        let images = json["images"] as? [[String: Any]] ?? []
        for (index, image) in images.enumerated() {
            if let viewIndex = GLTFJSON.int(image["bufferView"]) {
                guard views.indices.contains(viewIndex),
                      let length = GLTFJSON.int(views[viewIndex]["byteLength"]),
                      length <= GLTFResourceLimits.maxImageBytes,
                      let data = bufferViewBytes(viewIndex),
                      data.count <= GLTFResourceLimits.maxImageBytes
                else {
                    throw GLTFDocumentJSON.Error.invalidResource("Image \(index) references an invalid buffer view.")
                }
            } else if let uri = image["uri"] as? String {
                guard bytes(forURI: uri, limit: GLTFResourceLimits.maxImageBytes) != nil else {
                    throw GLTFDocumentJSON.Error.invalidResource("Image \(index) could not be read.")
                }
            }
        }
    }

    private func resolvedSidecar(_ uri: String) -> URL? {
        guard let fileURL, !uri.isEmpty,
              let decoded = uri.removingPercentEncoding,
              !decoded.hasPrefix("/"),
              !(URL(string: decoded)?.isFileURL ?? true)
        else { return nil }
        let base = fileURL.deletingLastPathComponent().standardizedFileURL
        let sidecar = base.appendingPathComponent(decoded).standardizedFileURL
        let basePath = base.path.hasSuffix("/") ? base.path : base.path + "/"
        guard sidecar.path == base.path || sidecar.path.hasPrefix(basePath) else { return nil }
        return sidecar
    }

    private func elementSize(_ accessor: [String: Any]) -> Int? {
        let components: Int
        switch GLTFJSON.int(accessor["componentType"]) {
        case 5120, 5121: components = 1
        case 5122, 5123: components = 2
        case 5125, 5126: components = 4
        default: return nil
        }
        switch accessor["type"] as? String {
        case "SCALAR": return components
        case "VEC2": return components * 2
        case "VEC3": return components * 3
        case "VEC4": return components * 4
        case "MAT2": return components * 4
        case "MAT3": return components * 9
        case "MAT4": return components * 16
        default: return nil
        }
    }
}
