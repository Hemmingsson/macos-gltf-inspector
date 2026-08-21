import Foundation
import ImageIO

/// Mesh / material / node / texture from the glTF JSON header. Animation count
/// comes from converted usable clips, not `json["animations"]`.
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
    /// Longest edge among decoded images (`max(width, height)`). Nil when unknown.
    let maxTextureEdge: Int?
    let hasVertexColors: Bool
    let isRigged: Bool
    let morphGeometryCount: Int
    let fileSizeBytes: Int64?

    static func from(json: [String: Any], fileSizeBytes: Int64? = nil) -> PreviewStats {
        fromJSONCounts(json, animationCount: 0, fileSizeBytes: fileSizeBytes, resourceURL: nil)
    }

    static func from(
        json: [String: Any],
        animationCount: Int,
        fileSizeBytes: Int64? = nil,
        resourceURL: URL? = nil
    ) -> PreviewStats {
        fromJSONCounts(
            json,
            animationCount: animationCount,
            fileSizeBytes: fileSizeBytes,
            resourceURL: resourceURL
        )
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

    private static func fromJSONCounts(
        _ json: [String: Any],
        animationCount: Int,
        fileSizeBytes: Int64?,
        resourceURL: URL?
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
            maxTextureEdge: maxTextureEdge(json: json, resourceURL: resourceURL),
            hasVertexColors: geometry.hasColors,
            isRigged: !skins.isEmpty || geometry.hasJoints,
            morphGeometryCount: geometry.morphMeshes,
            fileSizeBytes: fileSizeBytes
        )
    }

    /// Max `max(width, height)` via ImageIO properties (header read, not full raster).
    private static func maxTextureEdge(json: [String: Any], resourceURL: URL?) -> Int? {
        let images = json["images"] as? [[String: Any]] ?? []
        guard !images.isEmpty else { return nil }
        let bufferViews = json["bufferViews"] as? [[String: Any]] ?? []
        let bin = glbBin(from: resourceURL)
        let baseDir = resourceURL?.deletingLastPathComponent()
        var maxEdge = 0
        for image in images {
            guard let data = imageBytes(image, bin: bin, bufferViews: bufferViews, baseDir: baseDir),
                  let edge = imageMaxEdge(data)
            else { continue }
            maxEdge = max(maxEdge, edge)
        }
        return maxEdge > 0 ? maxEdge : nil
    }

    private static func glbBin(from url: URL?) -> Data? {
        guard let url, url.pathExtension.lowercased() == "glb",
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              let box = try? GLBBox.parse(data)
        else { return nil }
        return box.bin
    }

    private static func imageBytes(
        _ image: [String: Any],
        bin: Data?,
        bufferViews: [[String: Any]],
        baseDir: URL?
    ) -> Data? {
        if let viewIndex = GLBBox.intValue(image["bufferView"]),
           bufferViews.indices.contains(viewIndex),
           let bin {
            let view = bufferViews[viewIndex]
            let offset = GLBBox.intValue(view["byteOffset"]) ?? 0
            let length = GLBBox.intValue(view["byteLength"]) ?? 0
            guard offset >= 0, length > 0, offset + length <= bin.count else { return nil }
            return bin.subdata(in: offset..<(offset + length))
        }
        if let uri = image["uri"] as? String, !uri.isEmpty {
            if uri.hasPrefix("data:"), let comma = uri.firstIndex(of: ",") {
                let payload = String(uri[uri.index(after: comma)...])
                return Data(base64Encoded: payload)
            }
            guard let baseDir else { return nil }
            let file = URL(fileURLWithPath: uri, relativeTo: baseDir)
            return try? Data(contentsOf: file, options: [.mappedIfSafe])
        }
        return nil
    }

    private static func imageMaxEdge(_ data: Data) -> Int? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }
        let width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        let edge = max(width, height)
        return edge > 0 ? edge : nil
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
