import Foundation

/// GLTFKit2 0.5.15 only parses `EXT_meshopt_compression` and its own decoder predates vertex
/// codec v1 and the COLOR filter of `KHR_meshopt_compression`. Before GLTFKit2 sees the file,
/// decode every compressed bufferView (either extension) with the official meshoptimizer
/// decoder, point it at a decoded binary chunk and hand GLTFKit2 an in-memory GLB without the
/// extension. External buffers and images are folded into its binary chunk, because GLTFKit2
/// resolves files against the asset URL, which an in-memory asset does not have.
enum MetalMeshoptPreprocessor {
    static let extensionNames = ["KHR_meshopt_compression", "EXT_meshopt_compression"]

    /// Returns nil when the file uses no meshopt compression.
    static func decodedGLB(url: URL) throws -> Data? {
        let file = try Data(contentsOf: url, options: .mappedIfSafe)
        var jsonData = file
        var bin: Data?
        if file.count >= 12, file.prefix(4) == Data("glTF".utf8) {
            (jsonData, bin) = try splitGLB(file)
        }
        guard extensionNames.contains(where: { jsonData.range(of: Data($0.utf8)) != nil }) else { return nil }
        guard var root = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw MetalSceneError.invalid("glTF JSON is not an object")
        }
        let buffers = root["buffers"] as? [[String: Any]] ?? []
        var views = root["bufferViews"] as? [[String: Any]] ?? []
        let directory = url.deletingLastPathComponent()
        var loaded: [Int: Data] = [:]
        func bufferData(_ index: Int) throws -> Data {
            if let data = loaded[index] { return data }
            guard buffers.indices.contains(index) else { throw MetalSceneError.invalid("Buffer index is out of range") }
            let data: Data
            if let uri = buffers[index]["uri"] as? String {
                data = try load(uri: uri, directory: directory)
            } else if index == 0, let bin {
                data = bin
            } else { throw MetalSceneError.invalid("Buffer has no data") }
            loaded[index] = data
            return data
        }

        // In-memory GLTFKit2 assets cannot resolve buffer files, so every referenced original
        // buffer is copied into the single binary chunk, followed by the decoded views.
        var decodedViews = Set<Int>()
        for (i, view) in views.enumerated() {
            let ext = view["extensions"] as? [String: Any] ?? [:]
            if extensionNames.contains(where: { ext[$0] != nil }) { decodedViews.insert(i) }
        }
        var decoded = Data()
        var base: [Int: Int] = [:]
        for (i, view) in views.enumerated() where !decodedViews.contains(i) {
            guard let b = view["buffer"] as? Int else { throw MetalSceneError.invalid("bufferView \(i) has no buffer") }
            if base[b] == nil { base[b] = decoded.count; decoded.append(try bufferData(b)); pad(&decoded) }
        }
        for (i, var view) in views.enumerated() where !decodedViews.contains(i) {
            let b = view["buffer"] as? Int ?? 0
            view["byteOffset"] = (view["byteOffset"] as? Int ?? 0) + base[b, default: 0]
            view["buffer"] = 0
            views[i] = view
        }
        for (viewIndex, var view) in views.enumerated() {
            var extensions = view["extensions"] as? [String: Any] ?? [:]
            guard let name = extensionNames.first(where: { extensions[$0] != nil }),
                  let ext = extensions[name] as? [String: Any] else { continue }
            guard let source = ext["buffer"] as? Int, let length = ext["byteLength"] as? Int,
                  let stride = ext["byteStride"] as? Int, let count = ext["count"] as? Int,
                  let modeName = ext["mode"] as? String else {
                throw MetalSceneError.invalid("Incomplete \(name) on bufferView \(viewIndex)")
            }
            let offset = ext["byteOffset"] as? Int ?? 0
            let modes = ["ATTRIBUTES": 0, "TRIANGLES": 1, "INDICES": 2]
            let filters = ["NONE": 0, "OCTAHEDRAL": 1, "QUATERNION": 2, "EXPONENTIAL": 3, "COLOR": 4]
            guard let mode = modes[modeName], let filter = filters[ext["filter"] as? String ?? "NONE"],
                  name == "KHR_meshopt_compression" || filter != 4 else {
                throw MetalSceneError.invalid("Unsupported \(name) mode or filter on bufferView \(viewIndex)")
            }
            let input = try bufferData(source)
            guard offset >= 0, length >= 0, offset + length <= input.count, count >= 0, stride > 0 else {
                throw MetalSceneError.invalid("Meshopt bufferView \(viewIndex) is out of range")
            }
            let viewLength = view["byteLength"] as? Int ?? count * stride
            var output = Data(count: max(viewLength, count * stride))
            let ok = output.withUnsafeMutableBytes { out in
                input.withUnsafeBytes { raw in
                    GLTFMetalMeshoptDecode(out.baseAddress, count, stride,
                                           raw.baseAddress!.assumingMemoryBound(to: UInt8.self) + offset, length,
                                           Int32(mode), Int32(filter))
                }
            }
            guard ok else { throw MetalSceneError.invalid("Meshopt decoding failed on bufferView \(viewIndex)") }
            view["buffer"] = 0
            view["byteOffset"] = decoded.count
            view["byteLength"] = viewLength
            extensions[name] = nil
            view["extensions"] = extensions.isEmpty ? nil : extensions
            views[viewIndex] = view
            decoded.append(output.prefix(viewLength))
            pad(&decoded)
        }

        // GLTFKit2 resolves image files against the asset URL, which an in-memory asset lacks.
        if var images = root["images"] as? [[String: Any]] {
            for (i, var image) in images.enumerated() {
                guard let uri = image["uri"] as? String, !uri.hasPrefix("data:") else { continue }
                let bytes = try load(uri: uri, directory: directory)
                image["uri"] = nil
                image["bufferView"] = views.count
                image["mimeType"] = image["mimeType"] ?? mimeType(uri: uri, bytes: bytes)
                views.append(["buffer": 0, "byteOffset": decoded.count, "byteLength": bytes.count])
                decoded.append(bytes); pad(&decoded)
                images[i] = image
            }
            root["images"] = images
        }
        root["buffers"] = [["byteLength": decoded.count]]
        root["bufferViews"] = views
        for key in ["extensionsUsed", "extensionsRequired"] {
            guard let list = root[key] as? [String] else { continue }
            let kept = list.filter { !extensionNames.contains($0) }
            root[key] = kept.isEmpty ? nil : kept
        }
        let json = try JSONSerialization.data(withJSONObject: root, options: [.withoutEscapingSlashes])
        return makeGLB(json: json, bin: decoded)
    }

    private static func splitGLB(_ file: Data) throws -> (Data, Data?) {
        func u32(_ at: Int) -> Int { Int(file.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: at, as: UInt32.self).littleEndian }) }
        let total = min(u32(8), file.count)
        var offset = 12
        var json: Data?, bin: Data?
        while offset + 8 <= total {
            let length = u32(offset), type = u32(offset + 4)
            let start = offset + 8
            guard start + length <= total else { throw MetalSceneError.invalid("Truncated GLB chunk") }
            let chunk = file.subdata(in: start..<start + length)
            if type == 0x4E4F534A { json = chunk } else if type == 0x004E4942, bin == nil { bin = chunk }
            offset = start + length
        }
        guard let json else { throw MetalSceneError.invalid("GLB has no JSON chunk") }
        return (json, bin)
    }

    private static func load(uri: String, directory: URL) throws -> Data {
        if uri.hasPrefix("data:") {
            guard let comma = uri.firstIndex(of: ","), uri[..<comma].hasSuffix(";base64"),
                  let data = Data(base64Encoded: String(uri[uri.index(after: comma)...])) else {
                throw MetalSceneError.invalid("Unsupported buffer data URI")
            }
            return data
        }
        let path = uri.removingPercentEncoding ?? uri
        return try Data(contentsOf: directory.appendingPathComponent(path), options: .mappedIfSafe)
    }

    private static func mimeType(uri: String, bytes: Data) -> String {
        switch (uri as NSString).pathExtension.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "webp": return "image/webp"
        case "ktx2": return "image/ktx2"
        default:
            if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
            if bytes.starts(with: [0xFF, 0xD8]) { return "image/jpeg" }
            if bytes.count >= 12, bytes[8..<12].elementsEqual("WEBP".utf8) { return "image/webp" }
            if bytes.starts(with: [0xAB, 0x4B, 0x54, 0x58, 0x20, 0x32, 0x30]) { return "image/ktx2" }
            return "image/png"
        }
    }

    private static func pad(_ data: inout Data, with byte: UInt8 = 0) {
        while data.count % 4 != 0 { data.append(byte) }
    }

    private static func makeGLB(json: Data, bin: Data) -> Data {
        var jsonChunk = json
        pad(&jsonChunk, with: 0x20)
        var out = Data()
        func put(_ value: Int) { var v = UInt32(value).littleEndian; withUnsafeBytes(of: &v) { out.append(contentsOf: $0) } }
        out.append(contentsOf: Array("glTF".utf8)); put(2)
        put(12 + 8 + jsonChunk.count + 8 + bin.count)
        put(jsonChunk.count); put(0x4E4F534A); out.append(jsonChunk)
        put(bin.count); put(0x004E4942); out.append(bin)
        return out
    }
}
