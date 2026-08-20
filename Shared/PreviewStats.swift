import Foundation
import RealityKit

/// Mesh / material / node / texture from the glTF JSON header. Animation count and
/// duration come from converted usable clips, not `json["animations"]`.
struct PreviewStats: Equatable {
    struct Row: Equatable {
        let label: String
        let value: String
    }

    let triangleCount: Int
    let vertexCount: Int
    let materialCount: Int
    let pbrLabel: String
    let animationCount: Int
    let textureCount: Int
    let hasUVLayers: Bool
    let hasVertexColors: Bool
    let isRigged: Bool
    let morphGeometryCount: Int
    let hasScaleTransforms: Bool
    let durationSeconds: Double?
    let fileSizeBytes: Int64?

    static func from(json: [String: Any], fileSizeBytes: Int64? = nil) -> PreviewStats {
        fromJSONCounts(json, animationCount: 0, durationSeconds: nil, fileSizeBytes: fileSizeBytes)
    }

    /// Animation fields come from converted usable clips (`duration > 0`), not JSON.
    @MainActor
    static func from(
        json: [String: Any],
        usableAnimations: [AnimationResource],
        fileSizeBytes: Int64? = nil
    ) -> PreviewStats {
        let durations = usableAnimations.map(\.definition.duration).filter { $0.isFinite && $0 > 0 }
        return fromJSONCounts(
            json,
            animationCount: usableAnimations.count,
            durationSeconds: durations.max(),
            fileSizeBytes: fileSizeBytes
        )
    }

    /// Spec rows with a value. Zeros, default Metalness, and “No” flags stay off the list.
    var previewRows: [Row] {
        var rows: [Row] = []
        if triangleCount > 0 {
            rows.append(Row(label: "Geometry", value: "Triangles \(compact(triangleCount))"))
        }
        if vertexCount > 0 {
            rows.append(Row(label: "Vertices", value: compact(vertexCount)))
        }
        if pbrLabel != "Metalness" {
            rows.append(Row(label: "PBR", value: pbrLabel))
        }
        if textureCount > 0 {
            rows.append(Row(label: "Textures", value: "\(textureCount)"))
        }
        if materialCount > 0 {
            rows.append(Row(label: "Materials", value: "\(materialCount)"))
        }
        if textureCount > 0, !hasUVLayers {
            rows.append(Row(label: "UV Layers", value: "No"))
        }
        if hasVertexColors {
            rows.append(Row(label: "Vertex colors", value: "Yes"))
        }
        if animationCount > 0 {
            rows.append(Row(label: "Animations", value: animationValue))
        }
        if isRigged {
            rows.append(Row(label: "Rigged geometries", value: "Yes"))
        }
        if morphGeometryCount > 0 {
            rows.append(Row(label: "Morph geometries", value: "\(morphGeometryCount)"))
        }
        if hasScaleTransforms {
            rows.append(Row(label: "Scale transformations", value: "Yes"))
        }
        if let fileSizeBytes, fileSizeBytes > 0 {
            rows.append(Row(label: "Size", value: Self.byteCountFormatter.string(fromByteCount: fileSizeBytes)))
        }
        return rows
    }

    private var animationValue: String {
        if let durationSeconds, durationSeconds > 0 {
            return "\(animationCount) · \(String(format: "%.1fs", durationSeconds))"
        }
        return "\(animationCount)"
    }

    var previewLines: [String] {
        previewRows.map { "\($0.label) \($0.value)" }
    }

    /// One left-aligned fact per line for Quick Look. `noun` is the dimmed unit.
    var overlayFacts: [Row] {
        var lines: [Row] = []
        if triangleCount > 0 {
            lines.append(Row(label: "triangles", value: compact(triangleCount)))
        }
        if vertexCount > 0 {
            lines.append(Row(label: "vertices", value: compact(vertexCount)))
        }
        if textureCount > 0 {
            lines.append(Row(label: "textures", value: "\(textureCount)"))
        }
        if materialCount > 0 {
            lines.append(Row(label: "materials", value: "\(materialCount)"))
        }
        if pbrLabel != "Metalness" {
            lines.append(Row(label: pbrLabel, value: ""))
        }
        if hasVertexColors {
            lines.append(Row(label: "vertex colors", value: ""))
        }
        if isRigged {
            lines.append(Row(label: "rigged", value: ""))
        }
        if morphGeometryCount > 0 {
            lines.append(Row(label: "morphs", value: "\(morphGeometryCount)"))
        }
        if let fileSizeBytes, fileSizeBytes > 0 {
            let size = Self.byteCountFormatter.string(fromByteCount: fileSizeBytes)
            if let split = size.lastIndex(of: " ") {
                lines.append(
                    Row(
                        label: String(size[size.index(after: split)...]),
                        value: String(size[..<split])
                    )
                )
            } else {
                lines.append(Row(label: "", value: size))
            }
        }
        return lines
    }

    var overlayLines: [String] {
        overlayFacts.map { fact in
            [fact.value, fact.label].filter { !$0.isEmpty }.joined(separator: " ")
        }
    }

    private static func fromJSONCounts(
        _ json: [String: Any],
        animationCount: Int,
        durationSeconds: Double?,
        fileSizeBytes: Int64?
    ) -> PreviewStats {
        let materials = json["materials"] as? [[String: Any]] ?? []
        let meshes = json["meshes"] as? [[String: Any]] ?? []
        let accessors = json["accessors"] as? [[String: Any]] ?? []
        let nodes = json["nodes"] as? [[String: Any]] ?? []
        let skins = json["skins"] as? [[String: Any]] ?? []
        let geometry = meshGeometry(meshes, accessors: accessors)
        return PreviewStats(
            triangleCount: geometry.triangles,
            vertexCount: geometry.vertices,
            materialCount: materials.count,
            pbrLabel: pbrLabel(materials),
            animationCount: animationCount,
            textureCount: arrayCount(json["textures"]),
            hasUVLayers: geometry.hasUVs,
            hasVertexColors: geometry.hasColors,
            isRigged: !skins.isEmpty || geometry.hasJoints,
            morphGeometryCount: geometry.morphMeshes,
            hasScaleTransforms: nodes.contains { hasNonIdentityScale($0) },
            durationSeconds: durationSeconds,
            fileSizeBytes: fileSizeBytes
        )
    }

    private static func pbrLabel(_ materials: [[String: Any]]) -> String {
        var labels: [String] = []
        func add(_ label: String) {
            if !labels.contains(label) { labels.append(label) }
        }
        if materials.isEmpty {
            return "Metalness"
        }
        for material in materials {
            let extensions = material["extensions"] as? [String: Any]
            if extensions?["KHR_materials_unlit"] != nil {
                add("Unlit")
            } else if extensions?["KHR_materials_pbrSpecularGlossiness"] != nil {
                add("Specular")
            } else {
                add("Metalness")
            }
        }
        return labels.joined(separator: " + ")
    }

    private struct MeshGeometry {
        var triangles = 0
        var vertices = 0
        var hasUVs = false
        var hasColors = false
        var hasJoints = false
        var morphMeshes = 0
    }

    private static func meshGeometry(
        _ meshes: [[String: Any]],
        accessors: [[String: Any]]
    ) -> MeshGeometry {
        var out = MeshGeometry()
        for mesh in meshes {
            let primitives = mesh["primitives"] as? [[String: Any]] ?? []
            var meshHasMorph = false
            if let weights = mesh["weights"] as? [Any], !weights.isEmpty {
                meshHasMorph = true
            }
            for primitive in primitives {
                let attributes = primitive["attributes"] as? [String: Any] ?? [:]
                if attributes.keys.contains(where: { $0.hasPrefix("TEXCOORD_") }) {
                    out.hasUVs = true
                }
                if attributes.keys.contains(where: { $0.hasPrefix("COLOR_") }) {
                    out.hasColors = true
                }
                if attributes["JOINTS_0"] != nil {
                    out.hasJoints = true
                }
                if let targets = primitive["targets"] as? [Any], !targets.isEmpty {
                    meshHasMorph = true
                }
                out.vertices += accessorCount(attributes["POSITION"], accessors: accessors)
                let mode = GLBBox.intValue(primitive["mode"]) ?? 4
                let count: Int
                if let indices = primitive["indices"] {
                    count = accessorCount(indices, accessors: accessors)
                } else {
                    count = accessorCount(attributes["POSITION"], accessors: accessors)
                }
                switch mode {
                case 4:
                    out.triangles += count / 3
                case 5, 6:
                    out.triangles += max(0, count - 2)
                default:
                    break
                }
            }
            if meshHasMorph {
                out.morphMeshes += 1
            }
        }
        return out
    }

    private static func accessorCount(_ value: Any?, accessors: [[String: Any]]) -> Int {
        guard let index = GLBBox.intValue(value), accessors.indices.contains(index) else { return 0 }
        return GLBBox.intValue(accessors[index]["count"]) ?? 0
    }

    private static func hasNonIdentityScale(_ node: [String: Any]) -> Bool {
        if let scale = float3(node["scale"]) {
            return scale.contains { abs($0 - 1) > 1e-4 }
        }
        guard let matrix = float16(node["matrix"]) else { return false }
        let sx = hypot3(matrix[0], matrix[1], matrix[2])
        let sy = hypot3(matrix[4], matrix[5], matrix[6])
        let sz = hypot3(matrix[8], matrix[9], matrix[10])
        return abs(sx - 1) > 1e-3 || abs(sy - 1) > 1e-3 || abs(sz - 1) > 1e-3
    }

    private static func float3(_ value: Any?) -> [Double]? {
        guard let values = value as? [Any] else { return nil }
        let numbers = values.compactMap(GLBBox.doubleValue)
        return numbers.count >= 3 ? Array(numbers.prefix(3)) : nil
    }

    private static func float16(_ value: Any?) -> [Double]? {
        guard let values = value as? [Any] else { return nil }
        let numbers = values.compactMap(GLBBox.doubleValue)
        return numbers.count == 16 ? numbers : nil
    }

    private static func hypot3(_ x: Double, _ y: Double, _ z: Double) -> Double {
        sqrt(x * x + y * y + z * z)
    }

    private static func arrayCount(_ value: Any?) -> Int {
        (value as? [Any])?.count ?? 0
    }

    private func compact(_ value: Int) -> String {
        let magnitude = abs(value)
        if magnitude < 1000 {
            return "\(value)"
        }
        if magnitude < 1_000_000 {
            return trimCompact(Double(value) / 1000, suffix: "k")
        }
        return trimCompact(Double(value) / 1_000_000, suffix: "M")
    }

    private func trimCompact(_ value: Double, suffix: String) -> String {
        if abs(value.rounded() - value) < 0.05 {
            return String(format: "%.0f%@", value.rounded(), suffix)
        }
        return String(format: "%.1f%@", value, suffix)
    }

    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()
}
