import simd

/// Axis-aligned model bounds in authored glTF space (meters), from the JSON alone.
///
/// Each mesh node contributes its `POSITION` accessor `min`/`max` box, transformed by the node's
/// world matrix, and the boxes are unioned. No vertex data is read, so this is cheap. Deliberate
/// simplifications: skins
/// and morph targets are ignored (bind pose / base shape, from the accessor bounds), and
/// `EXT_mesh_gpu_instancing` instances are not expanded.
public struct ModelBounds: Sendable, Equatable {
    public var min: SIMD3<Float>
    public var max: SIMD3<Float>

    public init(min: SIMD3<Float>, max: SIMD3<Float>) {
        self.min = min
        self.max = max
    }

    public var size: SIMD3<Float> { max - min }
    public var center: SIMD3<Float> { (min + max) * 0.5 }

    /// Bounds of the default scene (`scene`, else scene 0, else every root node). Nil when no
    /// mesh node carries usable `POSITION` bounds.
    public static func from(json: [String: Any]) -> ModelBounds? {
        let nodes = json["nodes"] as? [[String: Any]] ?? []
        let meshes = json["meshes"] as? [[String: Any]] ?? []
        let accessors = json["accessors"] as? [[String: Any]] ?? []
        let scenes = json["scenes"] as? [[String: Any]] ?? []

        let roots: [Int]
        let sceneIndex = GLTFJSON.int(json["scene"]) ?? 0
        if scenes.indices.contains(sceneIndex) {
            roots = GLTFJSON.ints(scenes[sceneIndex]["nodes"])
        } else {
            let children = Set(nodes.flatMap { GLTFJSON.ints($0["children"]) })
            roots = nodes.indices.filter { !children.contains($0) }
        }

        var boxes: [ModelBounds] = []
        var visited = Set<Int>()
        func walk(_ index: Int, parent: simd_double4x4) {
            guard nodes.indices.contains(index), visited.insert(index).inserted else { return }
            let node = nodes[index]
            let world = parent * localMatrix(node)
            if let meshIndex = GLTFJSON.int(node["mesh"]), meshes.indices.contains(meshIndex),
               let local = meshBounds(meshes[meshIndex], accessors: accessors) {
                boxes.append(local.transformed(by: world))
            }
            for child in GLTFJSON.ints(node["children"]) {
                walk(child, parent: world)
            }
        }
        for root in roots {
            walk(root, parent: matrix_identity_double4x4)
        }
        return union(boxes)
    }

    /// Union of `boxes`, dropping non-finite and empty ones.
    static func union(_ boxes: [ModelBounds]) -> ModelBounds? {
        let kept = boxes.filter { $0.isFinite && !$0.isEmpty }
        guard !kept.isEmpty else { return nil }
        var minBound = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maxBound = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for box in kept {
            minBound = simd_min(minBound, box.min)
            maxBound = simd_max(maxBound, box.max)
        }
        return ModelBounds(min: minBound, max: maxBound)
    }

    var isEmpty: Bool { any(max .< min) }

    var isFinite: Bool {
        (0..<3).allSatisfy { min[$0].isFinite && max[$0].isFinite }
    }

    private func transformed(by matrix: simd_double4x4) -> ModelBounds {
        var minBound = SIMD3<Double>(repeating: .greatestFiniteMagnitude)
        var maxBound = SIMD3<Double>(repeating: -.greatestFiniteMagnitude)
        for corner in 0..<8 {
            let point = SIMD3<Double>(
                Double(corner & 1 == 0 ? min.x : max.x),
                Double(corner & 2 == 0 ? min.y : max.y),
                Double(corner & 4 == 0 ? min.z : max.z)
            )
            let moved = matrix * SIMD4<Double>(point, 1)
            let p = SIMD3<Double>(moved.x, moved.y, moved.z)
            minBound = simd_min(minBound, p)
            maxBound = simd_max(maxBound, p)
        }
        return ModelBounds(min: SIMD3<Float>(minBound), max: SIMD3<Float>(maxBound))
    }

    /// Union of the mesh's primitive `POSITION` bounds, in mesh space.
    private static func meshBounds(_ mesh: [String: Any], accessors: [[String: Any]]) -> ModelBounds? {
        var result: ModelBounds?
        for primitive in mesh["primitives"] as? [[String: Any]] ?? [] {
            let attributes = primitive["attributes"] as? [String: Any] ?? [:]
            guard let index = GLTFJSON.int(attributes["POSITION"]), accessors.indices.contains(index),
                  let box = accessorBounds(accessors[index])
            else { continue }
            result = result.map { ModelBounds(min: simd_min($0.min, box.min), max: simd_max($0.max, box.max)) } ?? box
        }
        return result
    }

    /// `min`/`max` of a `VEC3` accessor, dequantized when `normalized` (KHR_mesh_quantization).
    private static func accessorBounds(_ accessor: [String: Any]) -> ModelBounds? {
        guard let lo = GLTFJSON.doubles(accessor["min"]), lo.count >= 3,
              let hi = GLTFJSON.doubles(accessor["max"]), hi.count >= 3
        else { return nil }
        // Normalized integers map to [0, 1] / [-1, 1]; signed ones clamp at -1 (glTF spec).
        var scale = 1.0
        var floor = -Double.infinity
        if accessor["normalized"] as? Bool == true {
            switch GLTFJSON.int(accessor["componentType"]) {
            case 5120: (scale, floor) = (1.0 / 127, -1)
            case 5121: scale = 1.0 / 255
            case 5122: (scale, floor) = (1.0 / 32767, -1)
            case 5123: scale = 1.0 / 65535
            default: break
            }
        }
        func vector(_ values: [Double]) -> SIMD3<Float> {
            SIMD3<Float>((0..<3).map { Float(Swift.max(values[$0] * scale, floor)) })
        }
        return ModelBounds(min: vector(lo), max: vector(hi))
    }

    private static func localMatrix(_ node: [String: Any]) -> simd_double4x4 {
        if let m = GLTFJSON.doubles(node["matrix"]), m.count == 16 {
            return simd_double4x4(columns: (
                SIMD4(m[0], m[1], m[2], m[3]),
                SIMD4(m[4], m[5], m[6], m[7]),
                SIMD4(m[8], m[9], m[10], m[11]),
                SIMD4(m[12], m[13], m[14], m[15])
            ))
        }
        let t = GLTFJSON.doubles(node["translation"]) ?? [0, 0, 0]
        let r = GLTFJSON.doubles(node["rotation"]) ?? [0, 0, 0, 1]
        let s = GLTFJSON.doubles(node["scale"]) ?? [1, 1, 1]
        guard t.count == 3, r.count == 4, s.count == 3 else { return matrix_identity_double4x4 }
        var translation = matrix_identity_double4x4
        translation.columns.3 = SIMD4(t[0], t[1], t[2], 1)
        let rotation = simd_double4x4(simd_quatd(ix: r[0], iy: r[1], iz: r[2], r: r[3]).normalized)
        let scale = simd_double4x4(diagonal: SIMD4(s[0], s[1], s[2], 1))
        return translation * rotation * scale
    }
}
