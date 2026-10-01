import Foundation

/// Mesh / material / node / texture counts from the glTF JSON header (image headers for
/// `maxTextureEdge`). The caller supplies the animation count: playable clips on RealityKit,
/// JSON clips with a duration on WebKit.
public struct PreviewStats: Equatable {
    public struct Row: Equatable {
        public let label: String
        public let value: String
    }

    public let triangleCount: Int
    public let vertexCount: Int
    public let materialCount: Int
    public let pbrLabel: String
    public let animationCount: Int
    public let textureCount: Int
    /// Longest edge among decoded images (`max(width, height)`). Nil when unknown.
    public let maxTextureEdge: Int?
    public let hasVertexColors: Bool
    public let isRigged: Bool
    public let morphGeometryCount: Int
    public let fileSizeBytes: Int64?

    /// Placeholder before a model loads.
    public static let empty = PreviewStats(
        triangleCount: 0,
        vertexCount: 0,
        materialCount: 0,
        pbrLabel: "—",
        animationCount: 0,
        textureCount: 0,
        maxTextureEdge: nil,
        hasVertexColors: false,
        isRigged: false,
        morphGeometryCount: 0,
        fileSizeBytes: nil
    )

    public static func from(
        json: [String: Any],
        animationCount: Int = 0,
        fileSizeBytes: Int64? = nil,
        resourceURL: URL? = nil
    ) -> PreviewStats {
        from(
            json: json,
            animationCount: animationCount,
            fileSizeBytes: fileSizeBytes,
            binary: GLTFBinaryStore(json: json, fileURL: resourceURL)
        )
    }

    /// One left-aligned fact per line for Quick Look. `noun` is the dimmed unit.
    public var overlayFacts: [Row] {
        var lines: [Row] = []
        if triangleCount > 0 {
            lines.append(Row(label: "triangles", value: Self.compactCount(triangleCount)))
        }
        if vertexCount > 0 {
            lines.append(Row(label: "vertices", value: Self.compactCount(vertexCount)))
        }
        if textureCount > 0 {
            let value = maxTextureEdge.map { "\(textureCount) · max \($0)²" } ?? "\(textureCount)"
            lines.append(Row(label: "textures", value: value))
        }
        if materialCount > 0 {
            lines.append(Row(label: "materials", value: "\(materialCount)"))
        }
        if animationCount > 0 {
            lines.append(Row(label: "animations", value: "\(animationCount)"))
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

    /// `binary` resolves image bytes for `maxTextureEdge`; share one with the document parse.
    static func from(
        json: [String: Any],
        animationCount: Int,
        fileSizeBytes: Int64?,
        binary: GLTFBinaryStore
    ) -> PreviewStats {
        let materials = json["materials"] as? [[String: Any]] ?? []
        let meshes = json["meshes"] as? [[String: Any]] ?? []
        let accessors = json["accessors"] as? [[String: Any]] ?? []
        let skins = json["skins"] as? [[String: Any]] ?? []
        let geometry = meshGeometry(meshes, accessors: accessors)
        return PreviewStats(
            triangleCount: geometry.triangles,
            vertexCount: geometry.vertices,
            materialCount: materials.count,
            pbrLabel: pbrLabel(materials),
            animationCount: animationCount,
            textureCount: (json["textures"] as? [Any])?.count ?? 0,
            maxTextureEdge: maxTextureEdge(json: json, binary: binary),
            hasVertexColors: geometry.hasColors,
            isRigged: !skins.isEmpty || geometry.hasJoints,
            morphGeometryCount: geometry.morphMeshes,
            fileSizeBytes: fileSizeBytes
        )
    }

    /// Max `max(width, height)` from the image headers (no full raster decode).
    private static func maxTextureEdge(json: [String: Any], binary: GLTFBinaryStore) -> Int? {
        let images = json["images"] as? [[String: Any]] ?? []
        let edges = images.compactMap { image in
            binary.imageBytes(image).flatMap(GLTFImageDecode.pixelSize).map { max($0.width, $0.height) }
        }
        return edges.max()
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

    /// `1234` → `1.2k`, `2_000_000` → `2M`; below 1000 the plain count.
    public static func compactCount(_ value: Int) -> String {
        let magnitude = abs(value)
        if magnitude < 1000 {
            return "\(value)"
        }
        if magnitude < 1_000_000 {
            return trimCompact(Double(value) / 1000, suffix: "k")
        }
        return trimCompact(Double(value) / 1_000_000, suffix: "M")
    }

    private static func trimCompact(_ value: Double, suffix: String) -> String {
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
