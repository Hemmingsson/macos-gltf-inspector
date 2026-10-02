import AppKit
import GLTFCore
import SwiftUI

// First-paint status for the web canvas: a non-opaque pill, its copy, and the JSON counts behind it.

/// Small status pill over a clear field so a Quick Look poster (or the live canvas) stays visible.
struct WebCanvasLoadingChrome: View {
    var title: String
    var detail: String?
    /// Bottom over a cached poster; center when there is no stand-in picture.
    var pin: Alignment = .bottom

    var body: some View {
        VStack(spacing: 4) {
            ProgressView()
                .controlSize(.small)
                .progressViewStyle(.circular)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 11, weight: .medium))
            if let detail {
                Text(detail)
                    .font(.system(size: 10))
                    .opacity(0.7)
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: pin)
        .padding(.bottom, pin == .bottom ? 16 : 0)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel([title, detail].compactMap { $0 }.joined(separator: ". "))
    }
}

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
    static let drawing = "Drawing first frame…"

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

    /// File facts from the JSON header. Always lists what the peek found.
    static func detail(for inventory: WebRendererAssetInventory?) -> String? {
        guard let inventory else { return nil }
        var parts: [String] = []
        if inventory.meshCount > 0 {
            parts.append(inventory.meshCount == 1 ? "1 mesh" : "\(inventory.meshCount) meshes")
        }
        if inventory.triangleCount > 0 {
            parts.append("\(PreviewStats.compactCount(inventory.triangleCount)) triangles")
        }
        if inventory.materialCount > 0 {
            parts.append(inventory.materialCount == 1 ? "1 material" : "\(inventory.materialCount) materials")
        }
        if inventory.rasterCount > 0 {
            parts.append(inventory.rasterCount == 1 ? "1 texture" : "\(inventory.rasterCount) textures")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
