import Foundation

/// GLTFKit2 0.5.15 only parses `EXT_meshopt_compression` and its own decoder predates vertex
/// codec v1 and the COLOR filter of `KHR_meshopt_compression`. Before GLTFKit2 sees the file,
/// decode every compressed bufferView (either extension) with the official meshoptimizer
/// decoder, point it at a decoded binary chunk and hand GLTFKit2 an in-memory GLB without the
/// extension. External buffers and images are folded into its binary chunk, because GLTFKit2
/// resolves files against the asset URL, which an in-memory asset does not have.
enum MetalMeshoptPreprocessor {
    static let extensionNames = ["KHR_meshopt_compression", "EXT_meshopt_compression"]

    static func preflight(url: URL) throws {
        let (jsonData, bin) = try source(url: url)
        guard let root = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw MetalSceneError.invalid("glTF JSON is not an object")
        }
        let buffers = root["buffers"] as? [[String: Any]] ?? []
        let directory = url.deletingLastPathComponent()
        var bufferLengths: [Int] = []
        for buffer in buffers {
            guard let length = buffer["byteLength"] as? Int, length >= 0,
                  length <= MetalResourceLimits.maxSingleAllocationBytes else {
                throw MetalSceneError.invalid("Buffer length is invalid")
            }
            if let uri = buffer["uri"] as? String {
                let actual = try load(uri: uri, directory: directory).count
                guard actual >= length else { throw MetalSceneError.invalid("Buffer is truncated") }
            } else if let bin {
                guard bin.count >= length else { throw MetalSceneError.invalid("GLB buffer is truncated") }
            }
            bufferLengths.append(length)
        }
        let views = root["bufferViews"] as? [[String: Any]] ?? []
        for view in views {
            guard let buffer = view["buffer"] as? Int, bufferLengths.indices.contains(buffer),
                  let length = view["byteLength"] as? Int, length >= 0,
                  length <= MetalResourceLimits.maxSingleAllocationBytes else {
                throw MetalSceneError.invalid("bufferView is invalid")
            }
            let extensions = view["extensions"] as? [String: Any] ?? [:]
            if let name = extensionNames.first(where: { extensions[$0] != nil }),
               let ext = extensions[name] as? [String: Any],
               let source = ext["buffer"] as? Int, bufferLengths.indices.contains(source),
               let sourceLength = ext["byteLength"] as? Int {
                let sourceOffset = ext["byteOffset"] as? Int ?? 0
                guard sourceLength >= 0, sourceOffset >= 0 else {
                    throw MetalSceneError.invalid("Meshopt source range is invalid")
                }
                let sourceEnd = try MetalResourceLimits.sum(sourceOffset, sourceLength, label: "Meshopt source range")
                guard sourceEnd <= bufferLengths[source] else {
                    throw MetalSceneError.invalid("Meshopt source is out of range")
                }
                continue
            }
            let offset = view["byteOffset"] as? Int ?? 0
            let end = try MetalResourceLimits.sum(offset, length, label: "bufferView range")
            guard offset >= 0, end <= bufferLengths[buffer] else {
                throw MetalSceneError.invalid("bufferView is out of range")
            }
            if let stride = view["byteStride"] as? Int {
                guard stride >= 4, stride <= 252, stride % 4 == 0 else {
                    throw MetalSceneError.invalid("bufferView byteStride is invalid")
                }
            }
        }
        let accessors = root["accessors"] as? [[String: Any]] ?? []
        for accessor in accessors {
            guard let count = accessor["count"] as? Int, count >= 0,
                  let componentType = accessor["componentType"] as? Int,
                  let type = accessor["type"] as? String,
                  let components = componentCount(type),
                  let componentBytes = componentSize(componentType) else {
                throw MetalSceneError.invalid("Accessor is invalid")
            }
            guard count <= MetalResourceLimits.maxSingleAllocationBytes / max(components * componentBytes, 1) else {
                throw MetalSceneError.invalid("Accessor is too large")
            }
            _ = try MetalResourceLimits.product(count, components * MemoryLayout<Float>.stride,
                                                 label: "Expanded accessor", limit: MetalResourceLimits.maxSingleAllocationBytes)
            guard let viewIndex = accessor["bufferView"] as? Int else { continue }
            guard views.indices.contains(viewIndex) else { throw MetalSceneError.invalid("Accessor bufferView is out of range") }
            let view = views[viewIndex]
            let viewLength = view["byteLength"] as? Int ?? 0
            let accessorOffset = accessor["byteOffset"] as? Int ?? 0
            let elementBytes = try MetalResourceLimits.product(components, componentBytes, label: "Accessor element size")
            let stride = view["byteStride"] as? Int ?? elementBytes
            guard accessorOffset >= 0, stride >= elementBytes else {
                throw MetalSceneError.invalid("Accessor stride or offset is invalid")
            }
            let span = count == 0 ? 0 : try MetalResourceLimits.sum(
                try MetalResourceLimits.product(count - 1, stride, label: "Accessor stride span"),
                elementBytes,
                label: "Accessor range"
            )
            let end = try MetalResourceLimits.sum(accessorOffset, span, label: "Accessor range")
            guard end <= viewLength else { throw MetalSceneError.invalid("Accessor is out of range") }
        }
        for mesh in root["meshes"] as? [[String: Any]] ?? [] {
            for primitive in mesh["primitives"] as? [[String: Any]] ?? [] {
                let attributes = primitive["attributes"] as? [String: Int] ?? [:]
                if let index = attributes["POSITION"], accessors.indices.contains(index),
                   let count = accessors[index]["count"] as? Int {
                    _ = try MetalResourceLimits.product(count, MemoryLayout<MetalVertex>.stride,
                                                        label: "Expanded vertices", limit: MetalResourceLimits.maxSingleAllocationBytes)
                }
            }
        }
    }

    /// Returns nil when the file uses no meshopt compression.
    static func decodedGLB(url: URL) throws -> Data? {
        let (jsonData, originalBin) = try source(url: url)
        let file = try Data(contentsOf: url, options: .mappedIfSafe)
        guard file.count <= MetalResourceLimits.maxSingleAllocationBytes else {
            throw MetalSceneError.invalid("glTF file is too large")
        }
        let bin = originalBin
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
            guard data.count <= MetalResourceLimits.maxSingleAllocationBytes else {
                throw MetalSceneError.invalid("Buffer is too large")
            }
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
            if base[b] == nil {
                let source = try bufferData(b)
                base[b] = decoded.count
                let end = try MetalResourceLimits.sum(decoded.count, source.count, label: "Rebuilt buffer")
                guard end <= MetalResourceLimits.maxSingleAllocationBytes else {
                    throw MetalSceneError.invalid("Rebuilt buffer is too large")
                }
                decoded.append(source)
                pad(&decoded)
            }
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
            let end = try MetalResourceLimits.sum(offset, length, label: "Meshopt source range")
            let decodedLength = try MetalResourceLimits.product(count, stride, label: "Meshopt decoded size",
                                                                 limit: MetalResourceLimits.maxSingleAllocationBytes)
            guard offset >= 0, length >= 0, end <= input.count, count >= 0, stride > 0 else {
                throw MetalSceneError.invalid("Meshopt bufferView \(viewIndex) is out of range")
            }
            let viewLength = view["byteLength"] as? Int ?? decodedLength
            let outputLength = max(viewLength, decodedLength)
            guard viewLength >= 0, outputLength <= MetalResourceLimits.maxSingleAllocationBytes else {
                throw MetalSceneError.invalid("Meshopt bufferView \(viewIndex) is too large")
            }
            var output = Data(count: outputLength)
            let ok = output.withUnsafeMutableBytes { out in
                input.withUnsafeBytes { raw in
                    guard let outputBase = out.baseAddress, let inputBase = raw.baseAddress else { return false }
                    return GLTFMetalMeshoptDecode(outputBase, count, stride,
                                                  inputBase.assumingMemoryBound(to: UInt8.self) + offset, length,
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
            let decodedEnd = try MetalResourceLimits.sum(decoded.count, viewLength, label: "Decoded buffer")
            guard decodedEnd <= MetalResourceLimits.maxSingleAllocationBytes else {
                throw MetalSceneError.invalid("Decoded buffer is too large")
            }
            decoded.append(output.prefix(viewLength))
            pad(&decoded)
        }

        // GLTFKit2 resolves image files against the asset URL, which an in-memory asset lacks.
        if var images = root["images"] as? [[String: Any]] {
            for (i, var image) in images.enumerated() {
                guard let uri = image["uri"] as? String, !uri.hasPrefix("data:") else { continue }
                let bytes = try load(uri: uri, directory: directory)
                guard bytes.count <= MetalResourceLimits.maxSingleAllocationBytes else {
                    throw MetalSceneError.invalid("Image is too large")
                }
                image["uri"] = nil
                image["bufferView"] = views.count
                image["mimeType"] = image["mimeType"] ?? mimeType(uri: uri, bytes: bytes)
                views.append(["buffer": 0, "byteOffset": decoded.count, "byteLength": bytes.count])
                let end = try MetalResourceLimits.sum(decoded.count, bytes.count, label: "Embedded image data")
                guard end <= MetalResourceLimits.maxSingleAllocationBytes else {
                    throw MetalSceneError.invalid("Embedded image data is too large")
                }
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
        return try makeGLB(json: json, bin: decoded)
    }

    private static func source(url: URL) throws -> (Data, Data?) {
        let file = try Data(contentsOf: url, options: .mappedIfSafe)
        guard file.count <= MetalResourceLimits.maxSingleAllocationBytes else {
            throw MetalSceneError.invalid("glTF file is too large")
        }
        if file.count >= 4, file.prefix(4) == Data("glTF".utf8) {
            return try splitGLB(file)
        }
        return (file, nil)
    }

    private static func componentCount(_ type: String) -> Int? {
        switch type {
        case "SCALAR": 1
        case "VEC2": 2
        case "VEC3": 3
        case "VEC4": 4
        case "MAT2": 4
        case "MAT3": 9
        case "MAT4": 16
        default: nil
        }
    }

    private static func componentSize(_ type: Int) -> Int? {
        switch type {
        case 5120, 5121: 1
        case 5122, 5123: 2
        case 5125, 5126: 4
        default: nil
        }
    }

    private static func splitGLB(_ file: Data) throws -> (Data, Data?) {
        func u32(_ at: Int) -> Int { Int(file.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: at, as: UInt32.self).littleEndian }) }
        guard file.count >= 12 else { throw MetalSceneError.invalid("Truncated GLB header") }
        let declaredLength = u32(8)
        guard declaredLength >= 12, declaredLength <= file.count else {
            throw MetalSceneError.invalid("GLB length is out of range")
        }
        let total = declaredLength
        var offset = 12
        var json: Data?, bin: Data?
        while offset + 8 <= total {
            let length = u32(offset), type = u32(offset + 4)
            let start = offset + 8
            let end = try MetalResourceLimits.sum(start, length, label: "GLB chunk range")
            guard end <= total else { throw MetalSceneError.invalid("Truncated GLB chunk") }
            let chunk = file.subdata(in: start..<start + length)
            if type == 0x4E4F534A { json = chunk } else if type == 0x004E4942, bin == nil { bin = chunk }
            offset = end
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

    private static func makeGLB(json: Data, bin: Data) throws -> Data {
        var jsonChunk = json
        pad(&jsonChunk, with: 0x20)
        var out = Data()
        func put(_ value: Int) throws {
            guard value >= 0, value <= Int(UInt32.max) else {
                throw MetalSceneError.invalid("Rebuilt GLB is too large")
            }
            var v = UInt32(value).littleEndian
            withUnsafeBytes(of: &v) { out.append(contentsOf: $0) }
        }
        out.append(contentsOf: Array("glTF".utf8)); try put(2)
        try put(12 + 8 + jsonChunk.count + 8 + bin.count)
        try put(jsonChunk.count); try put(0x4E4F534A); out.append(jsonChunk)
        try put(bin.count); try put(0x004E4942); out.append(bin)
        return out
    }
}
