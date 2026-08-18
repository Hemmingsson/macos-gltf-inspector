import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Rewrites a GLB so RealityKit convert can see meshes: float positions,
/// PNG textures, expanded GPU instances. Meshopt stays — GLTFKit2 decompresses it.
enum GLBRealityPrepare {
    private static let quantization = "KHR_mesh_quantization"
    private static let instancing = "EXT_mesh_gpu_instancing"
    private static let webp = "EXT_texture_webp"
    private static let floatType = 5126

    static func needsPrepare(_ json: [String: Any]) -> Bool {
        let used = (json["extensionsUsed"] as? [String]) ?? []
        if used.contains(quantization) || used.contains(instancing) || used.contains(webp) {
            return true
        }
        let skip = skipAccessorIndices(json)
        let accessors = json["accessors"] as? [[String: Any]] ?? []
        for (i, accessor) in accessors.enumerated() where !skip.contains(i) {
            if let type = GLBBox.intValue(accessor["componentType"]), isIntegerComponent(type) {
                return true
            }
        }
        let images = json["images"] as? [[String: Any]] ?? []
        if images.contains(where: { ($0["mimeType"] as? String)?.lowercased() == "image/webp" }) {
            return true
        }
        return hasUnnamedSkinJoints(json)
    }

    /// Float positions, PNG textures, expanded GPU instances — in memory. Serialization
    /// happens once at the end of the fused prepare in `GLBEntityLoader`.
    static func transformed(_ glb: GLBBox) throws -> GLBBox {
        var json = glb.json
        var bin = glb.bin
        dequantizeAccessors(&json, bin: &bin)
        try convertWebP(&json, bin: &bin)
        expandInstances(&json, bin: bin)
        nameUnnamedSkinJoints(&json)
        GLBBox.rewriteExtensionLists(&json, removing: [quantization, instancing, webp])
        GLBBox.setPrimaryBufferLength(&json, bin.count)
        return GLBBox(json: json, bin: bin)
    }

    /// Serializing wrapper kept for the unit tests, which assert on GLB bytes.
    static func convert(_ glb: GLBBox) throws -> Data {
        let out = try transformed(glb)
        return try GLBBox.serialize(json: out.json, bin: out.bin)
    }

    // MARK: - Dequantize

    static func dequantizeAccessors(_ json: inout [String: Any], bin: inout Data) {
        let skip = skipAccessorIndices(json)
        var accessors = json["accessors"] as? [[String: Any]] ?? []
        var bufferViews = json["bufferViews"] as? [[String: Any]] ?? []
        for i in accessors.indices where !skip.contains(i) {
            guard let componentType = GLBBox.intValue(accessors[i]["componentType"]),
                  isIntegerComponent(componentType),
                  let count = GLBBox.intValue(accessors[i]["count"]), count > 0
            else { continue }
            let dimension = componentCount(accessors[i]["type"] as? String)
            guard dimension > 0 else { continue }
            let normalized = accessors[i]["normalized"] as? Bool ?? false
            guard let values = readNumeric(
                accessor: accessors[i],
                bufferViews: bufferViews,
                bin: bin,
                normalized: normalized
            ) else { continue }
            var payload = Data(count: values.count * MemoryLayout<Float>.size)
            payload.withUnsafeMutableBytes { raw in
                let dest = raw.bindMemory(to: UInt32.self)
                for (index, value) in values.enumerated() {
                    dest[index] = Float(value).bitPattern.littleEndian
                }
            }
            let view = GLBBox.appendBytes(payload, bin: &bin, bufferViews: &bufferViews)
            accessors[i]["bufferView"] = view
            accessors[i]["byteOffset"] = 0
            accessors[i]["componentType"] = floatType
            accessors[i].removeValue(forKey: "normalized")
        }
        json["accessors"] = accessors
        json["bufferViews"] = bufferViews
    }

    // MARK: - WebP

    static func convertWebP(_ json: inout [String: Any], bin: inout Data) throws {
        var images = json["images"] as? [[String: Any]] ?? []
        var bufferViews = json["bufferViews"] as? [[String: Any]] ?? []
        for i in images.indices {
            let mime = (images[i]["mimeType"] as? String)?.lowercased()
            guard mime == "image/webp",
                  let viewIndex = GLBBox.intValue(images[i]["bufferView"]),
                  bufferViews.indices.contains(viewIndex)
            else { continue }
            let view = bufferViews[viewIndex]
            let offset = GLBBox.intValue(view["byteOffset"]) ?? 0
            let length = GLBBox.intValue(view["byteLength"]) ?? 0
            guard offset >= 0, length > 0, offset + length <= bin.count else { continue }
            let slice = bin.subdata(in: offset..<(offset + length))
            guard let png = pngFromImageData(slice) else { continue }
            let newView = GLBBox.appendBytes(png, bin: &bin, bufferViews: &bufferViews)
            images[i]["bufferView"] = newView
            images[i]["mimeType"] = "image/png"
        }
        json["images"] = images
        json["bufferViews"] = bufferViews
    }

    // MARK: - Instancing

    static func expandInstances(_ json: inout [String: Any], bin: Data) {
        var nodes = json["nodes"] as? [[String: Any]] ?? []
        let accessors = json["accessors"] as? [[String: Any]] ?? []
        let bufferViews = json["bufferViews"] as? [[String: Any]] ?? []
        let meshoptViews = meshoptViewIndices(json)
        var i = 0
        while i < nodes.count {
            guard let extensions = nodes[i]["extensions"] as? [String: Any],
                  let instancingExt = extensions[instancing] as? [String: Any],
                  let attributes = instancingExt["attributes"] as? [String: Any]
            else {
                i += 1
                continue
            }
            if instanceAttributesUseMeshopt(attributes, accessors: accessors, meshoptViews: meshoptViews) {
                i += 1
                continue
            }
            let translation = floatArray("TRANSLATION", attributes, accessors, bufferViews, bin)
            let rotation = floatArray("ROTATION", attributes, accessors, bufferViews, bin)
            let scale = floatArray("SCALE", attributes, accessors, bufferViews, bin)
            let count = max(translation.count / 3, max(rotation.count / 4, scale.count / 3))
            let finite = translation.allSatisfy(\.isFinite)
                && rotation.allSatisfy(\.isFinite)
                && scale.allSatisfy(\.isFinite)
            guard count > 0, finite else {
                removeExtension(instancing, from: &nodes[i])
                i += 1
                continue
            }
            var children = (nodes[i]["children"] as? [Int]) ?? []
            nodes.reserveCapacity(nodes.count + count)
            children.reserveCapacity(children.count + count)
            let prototype = instancePrototype(nodes[i])
            for instance in 0..<count {
                var clone = prototype
                clone["translation"] = slice(translation, at: instance, count: 3, fallback: [0, 0, 0])
                clone["rotation"] = slice(rotation, at: instance, count: 4, fallback: [0, 0, 0, 1])
                clone["scale"] = slice(scale, at: instance, count: 3, fallback: [1, 1, 1])
                nodes.append(clone)
                children.append(nodes.count - 1)
            }
            var original = nodes[i]
            original.removeValue(forKey: "mesh")
            original.removeValue(forKey: "skin")
            original.removeValue(forKey: "camera")
            removeExtension(instancing, from: &original)
            original["children"] = children
            nodes[i] = original
            i += 1
        }
        json["nodes"] = nodes
    }

    static func hasUnnamedSkinJoints(_ json: [String: Any]) -> Bool {
        var found = false
        visitSkinJoints(json) { _, _, name in
            if name.isEmpty { found = true }
        }
        return found
    }

    static func nameUnnamedSkinJoints(_ json: inout [String: Any]) {
        guard var nodes = json["nodes"] as? [[String: Any]] else { return }
        visitSkinJoints(json) { index, offset, name in
            if name.isEmpty {
                nodes[index]["name"] = GLBSkin.synthesizedName(index: offset)
            }
        }
        json["nodes"] = nodes
    }

    private static func visitSkinJoints(
        _ json: [String: Any],
        _ body: (_ nodeIndex: Int, _ jointOffset: Int, _ name: String) -> Void
    ) {
        let nodes = json["nodes"] as? [[String: Any]] ?? []
        let skins = json["skins"] as? [[String: Any]] ?? []
        for skin in skins {
            let joints = skin["joints"] as? [Any] ?? []
            for (offset, joint) in joints.enumerated() {
                guard let index = GLBBox.intValue(joint), nodes.indices.contains(index) else { continue }
                body(index, offset, nodes[index]["name"] as? String ?? "")
            }
        }
    }

    private static func instancePrototype(_ node: [String: Any]) -> [String: Any] {
        var clone: [String: Any] = [:]
        for (key, value) in node where key != "children" && key != "matrix" && key != "extensions" {
            clone[key] = value
        }
        if var extensions = node["extensions"] as? [String: Any] {
            extensions.removeValue(forKey: instancing)
            if !extensions.isEmpty { clone["extensions"] = extensions }
        }
        return clone
    }

    // MARK: - Helpers

    static func meshoptViewIndices(_ json: [String: Any]) -> Set<Int> {
        var views = Set<Int>()
        let bufferViews = json["bufferViews"] as? [[String: Any]] ?? []
        for (index, view) in bufferViews.enumerated() {
            if (view["extensions"] as? [String: Any])?["EXT_meshopt_compression"] != nil {
                views.insert(index)
            }
        }
        return views
    }

    private static func instanceAttributesUseMeshopt(
        _ attributes: [String: Any],
        accessors: [[String: Any]],
        meshoptViews: Set<Int>
    ) -> Bool {
        for value in attributes.values {
            guard let index = GLBBox.intValue(value), accessors.indices.contains(index),
                  let view = GLBBox.intValue(accessors[index]["bufferView"])
            else { continue }
            if meshoptViews.contains(view) { return true }
        }
        return false
    }

    static func skipAccessorIndices(_ json: [String: Any]) -> Set<Int> {
        var skip = Set<Int>()
        let meshes = json["meshes"] as? [[String: Any]] ?? []
        for mesh in meshes {
            let primitives = mesh["primitives"] as? [[String: Any]] ?? []
            for primitive in primitives {
                if let index = GLBBox.intValue(primitive["indices"]) {
                    skip.insert(index)
                }
                let attributes = primitive["attributes"] as? [String: Any] ?? [:]
                for (name, value) in attributes where name.hasPrefix("JOINTS") {
                    if let index = GLBBox.intValue(value) {
                        skip.insert(index)
                    }
                }
            }
        }
        let meshoptViews = meshoptViewIndices(json)
        let accessors = json["accessors"] as? [[String: Any]] ?? []
        for (index, accessor) in accessors.enumerated() {
            if let view = GLBBox.intValue(accessor["bufferView"]), meshoptViews.contains(view) {
                skip.insert(index)
            }
        }
        return skip
    }

    private static func removeExtension(_ name: String, from node: inout [String: Any]) {
        guard var extensions = node["extensions"] as? [String: Any] else { return }
        extensions.removeValue(forKey: name)
        if extensions.isEmpty {
            node.removeValue(forKey: "extensions")
        } else {
            node["extensions"] = extensions
        }
    }

    private static func slice(_ src: [Double], at index: Int, count: Int, fallback: [Double]) -> [Double] {
        let start = index * count
        guard start + count <= src.count else { return fallback }
        return Array(src[start..<(start + count)])
    }

    private static func isIntegerComponent(_ type: Int) -> Bool {
        type == 5120 || type == 5121 || type == 5122 || type == 5123 || type == 5125
    }

    private static func componentCount(_ type: String?) -> Int {
        switch type {
        case "SCALAR": return 1
        case "VEC2": return 2
        case "VEC3": return 3
        case "VEC4": return 4
        case "MAT2": return 4
        case "MAT3": return 9
        case "MAT4": return 16
        default: return 0
        }
    }

    private static func floatArray(
        _ attribute: String,
        _ attributes: [String: Any],
        _ accessors: [[String: Any]],
        _ bufferViews: [[String: Any]],
        _ bin: Data
    ) -> [Double] {
        guard let index = GLBBox.intValue(attributes[attribute]),
              accessors.indices.contains(index)
        else { return [] }
        return readNumeric(
            accessor: accessors[index],
            bufferViews: bufferViews,
            bin: bin,
            normalized: accessors[index]["normalized"] as? Bool ?? false
        ) ?? []
    }

    private static func readNumeric(
        accessor: [String: Any],
        bufferViews: [[String: Any]],
        bin: Data,
        normalized: Bool
    ) -> [Double]? {
        guard let viewIndex = GLBBox.intValue(accessor["bufferView"]),
              bufferViews.indices.contains(viewIndex),
              let count = GLBBox.intValue(accessor["count"]), count > 0,
              let componentType = GLBBox.intValue(accessor["componentType"])
        else { return nil }
        let dimension = componentCount(accessor["type"] as? String)
        guard dimension > 0 else { return nil }
        let view = bufferViews[viewIndex]
        let viewOffset = GLBBox.intValue(view["byteOffset"]) ?? 0
        let accessorOffset = GLBBox.intValue(accessor["byteOffset"]) ?? 0
        let elementSize = componentSize(componentType) * dimension
        let stride = GLBBox.intValue(view["byteStride"]) ?? elementSize
        let start = viewOffset + accessorOffset
        let values = count * dimension
        var out = [Double](repeating: 0, count: values)
        for i in 0..<count {
            let base = start + i * stride
            for c in 0..<dimension {
                let offset = base + c * componentSize(componentType)
                guard offset + componentSize(componentType) <= bin.count else { return nil }
                let raw = readComponent(bin, offset: offset, type: componentType)
                let index = i * dimension + c
                // glTF: normalized integers divide by the type max; non-normalized
                // integers (KHR_mesh_quantization) are used as-is and placed by the
                // node transform. `min`/`max` are descriptive bounds, not a remap range.
                out[index] = normalized ? normalize(raw, type: componentType) : raw
            }
        }
        return out
    }

    private static func componentSize(_ type: Int) -> Int {
        switch type {
        case 5120, 5121: return 1
        case 5122, 5123: return 2
        default: return 4
        }
    }

    private static func readComponent(_ data: Data, offset: Int, type: Int) -> Double {
        switch type {
        case 5120: return Double(Int8(bitPattern: data[offset]))
        case 5121: return Double(data[offset])
        case 5122: return Double(Int16(bitPattern: GLBBox.readUInt16(data, offset)))
        case 5123: return Double(GLBBox.readUInt16(data, offset))
        case 5125: return Double(GLBBox.readUInt32(data, offset))
        default: return Double(Float(bitPattern: GLBBox.readUInt32(data, offset)))
        }
    }

    private static func normalize(_ value: Double, type: Int) -> Double {
        switch type {
        case 5120: return max(value / 127, -1)
        case 5121: return value / 255
        case 5122: return max(value / 32767, -1)
        case 5123: return value / 65535
        default: return value
        }
    }

    private static func pngFromImageData(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let destData = CFDataCreateMutable(nil, 0),
              let dest = CGImageDestinationCreateWithData(destData, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return destData as Data
    }
}
