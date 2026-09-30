import Foundation
import GLTFCore

/// Rewrites a GLB so RealityKit convert can see meshes: expanded GPU instances. Meshopt, WebP
/// and quantized accessors stay — GLTFKit2 decompresses / decodes / converts them
/// (`Packed.floatData`); unnamed skin joints are named at convert (`Skin.resolvedName`).
enum RealityPrepare {
    private static let instancing = "EXT_mesh_gpu_instancing"

    static func needsPrepare(_ json: [String: Any]) -> Bool {
        ((json["extensionsUsed"] as? [String]) ?? []).contains(instancing)
    }

    /// Expanded GPU instances — in memory. Serialization
    /// happens once at the end of the fused prepare in `EntityLoader`.
    static func transformed(_ glb: GLBBox) throws -> GLBBox {
        var report = PreparePipelineReport()
        return try transformed(glb, report: &report)
    }

    static func transformed(_ glb: GLBBox, report: inout PreparePipelineReport) throws -> GLBBox {
        var json = glb.json
        let bin = glb.bin
        if expandInstances(&json, bin: bin) { report.gpuInstancesExpanded = true }
        GLBBox.rewriteExtensionLists(&json, removing: [instancing])
        GLBBox.setPrimaryBufferLength(&json, bin.count)
        return GLBBox(json: json, bin: bin)
    }

    /// Serializing wrapper kept for the unit tests, which assert on GLB bytes.
    static func convert(_ glb: GLBBox) throws -> Data {
        let out = try transformed(glb)
        return try GLBBox.serialize(json: out.json, bin: out.bin)
    }

    // MARK: - Instancing

    @discardableResult
    static func expandInstances(_ json: inout [String: Any], bin: Data) -> Bool {
        var nodes = json["nodes"] as? [[String: Any]] ?? []
        let accessors = json["accessors"] as? [[String: Any]] ?? []
        let bufferViews = json["bufferViews"] as? [[String: Any]] ?? []
        let meshoptViews = meshoptViewIndices(json)
        var changed = false
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
            changed = true
            i += 1
        }
        json["nodes"] = nodes
        return changed
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
}
