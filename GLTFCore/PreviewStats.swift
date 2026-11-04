import Foundation

/// Triangle / material / texture counts from the glTF JSON header (image headers for
/// `maxTextureEdge`). The caller supplies the animation count (JSON clips with a duration).
public struct PreviewStats: Equatable {
    public let triangleCount: Int
    public let materialCount: Int
    public let animationCount: Int
    public let textureCount: Int
    /// Longest edge among decoded images (`max(width, height)`). Nil when unknown.
    public let maxTextureEdge: Int?
    public let fileSizeBytes: Int64?

    /// Placeholder before a model loads.
    public static let empty = PreviewStats(
        triangleCount: 0,
        materialCount: 0,
        animationCount: 0,
        textureCount: 0,
        maxTextureEdge: nil,
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

    /// `binary` resolves image bytes for `maxTextureEdge`; share one with the document parse.
    static func from(
        json: [String: Any],
        animationCount: Int,
        fileSizeBytes: Int64?,
        binary: GLTFBinaryStore
    ) -> PreviewStats {
        let meshes = json["meshes"] as? [[String: Any]] ?? []
        let accessors = json["accessors"] as? [[String: Any]] ?? []
        let triangles = meshes
            .flatMap { $0["primitives"] as? [[String: Any]] ?? [] }
            .reduce(0) { $0 + GLTFJSON.triangleCount($1, accessors: accessors) }
        return PreviewStats(
            triangleCount: triangles,
            materialCount: (json["materials"] as? [Any])?.count ?? 0,
            animationCount: animationCount,
            textureCount: (json["textures"] as? [Any])?.count ?? 0,
            maxTextureEdge: maxTextureEdge(json: json, binary: binary),
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
}
