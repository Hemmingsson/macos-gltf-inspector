import Foundation
import GLTFCore

/// Counts from the glTF JSON header only — no BIN, no ImageIO.
struct WebRendererAssetInventory: Equatable, Sendable {
    var imageCount: Int
    var textureCount: Int
    var meshCount: Int
    var materialCount: Int
    var triangleCount: Int

    /// Rasters the renderer will decode. Prefer `images`; fall back to `textures`.
    var rasterCount: Int { max(imageCount, textureCount) }

    static func from(json: [String: Any]) -> Self {
        let stats = PreviewStats.from(json: json)
        return Self(
            imageCount: (json["images"] as? [Any])?.count ?? 0,
            textureCount: stats.textureCount,
            meshCount: (json["meshes"] as? [Any])?.count ?? 0,
            materialCount: stats.materialCount,
            triangleCount: stats.triangleCount
        )
    }

    static func peek(from url: URL) -> Self? {
        guard let json = try? GLBBox.peekDocumentJSON(from: url) else { return nil }
        return from(json: json)
    }
}

/// Honest first-paint status. Never invents a count the JSON does not have.
enum WebRendererLoadCopy {
    static let starting = "Starting renderer…"
    static let model = "Loading model…"
    /// First GPU frame after parse — this is the long blank if the spinner is already gone.
    static let drawing = "Drawing…"

    static func message(for inventory: WebRendererAssetInventory?) -> String {
        guard let inventory else { return model }
        let rasters = inventory.rasterCount
        if rasters > 0 {
            return rasters == 1 ? "Loading 1 texture…" : "Loading \(rasters) textures…"
        }
        if inventory.meshCount > 1 {
            return "Loading \(inventory.meshCount) meshes…"
        }
        if inventory.triangleCount > 0 {
            return "Loading \(PreviewStats.compactCount(inventory.triangleCount)) triangles…"
        }
        if inventory.materialCount > 1 {
            return "Loading \(inventory.materialCount) materials…"
        }
        return model
    }

    /// Extra facts when the headline is textures (or otherwise incomplete).
    static func detail(for inventory: WebRendererAssetInventory?) -> String? {
        guard let inventory else { return nil }
        var parts: [String] = []
        if inventory.rasterCount > 0 {
            if inventory.meshCount > 0 {
                parts.append(inventory.meshCount == 1 ? "1 mesh" : "\(inventory.meshCount) meshes")
            }
            if inventory.triangleCount > 0 {
                parts.append("\(PreviewStats.compactCount(inventory.triangleCount)) triangles")
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
