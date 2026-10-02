import DesignSystem
import SwiftUI

/// File-level stats rows. Shown in the left sidebar footer for a loaded model.
struct FileSection: View {
    var stats: Stats
    var fileName: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            DSSectionHeader("File")

            VStack(spacing: DS.Spacing.xs) {
                DSFactRow("Triangles", value: stats.triangleCount.formatted())
                DSFactRow(
                    "Meshes · Materials",
                    value: "\(stats.meshCount) · \(stats.materialCount)"
                )
                DSFactRow("Textures", value: texturesValue)
                if stats.animationCount > 0 {
                    DSFactRow("Animations", value: "\(stats.animationCount)")
                }
                if let size = fileSizeValue {
                    DSFactRow("File size", value: size)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("File \(fileName)")
        }
        .padding(.horizontal, DS.Spacing.l)
        .padding(.top, DS.Spacing.m)
        .padding(.bottom, DS.Spacing.s)
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

// MARK: - Previews

#Preview("cube") {
    PreviewCanvas(width: DS.Metrics.inspectorWidth) {
        let model = FixtureSceneModel.cube
        FileSection(stats: model.stats, fileName: model.fileName)
    }
}

#Preview("multi-scene") {
    PreviewCanvas(width: DS.Metrics.inspectorWidth) {
        let model = FixtureSceneModel.multiScene
        FileSection(stats: model.stats, fileName: model.fileName)
    }
}
