import SwiftUI

/// File-level stats rows. Always shown for a loaded model — selection does not hide the
/// document facts.
struct FileSection: View {
    var stats: Stats
    var fileName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InspectorSectionHeader(title: "File")

            VStack(spacing: 0) {
                InspectorFactRow(label: "Triangles", value: stats.triangleCount.formatted())
                InspectorFactRow(
                    label: "Meshes · Materials",
                    value: "\(stats.meshCount) · \(stats.materialCount)"
                )
                InspectorFactRow(label: "Textures", value: texturesValue)
                if stats.animationCount > 0 {
                    InspectorFactRow(label: "Animations", value: "\(stats.animationCount)")
                }
                if let size = fileSizeValue {
                    InspectorFactRow(label: "File size", value: size)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 2)
            .padding(.bottom, 10)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("File \(fileName)")
        }
    }

    private var texturesValue: String {
        if let max = stats.maxTextureDimension {
            return "\(stats.textureCount) · max \(max)²"
        }
        return "\(stats.textureCount)"
    }

    private var fileSizeValue: String? {
        guard let bytes = stats.fileSizeBytes else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
