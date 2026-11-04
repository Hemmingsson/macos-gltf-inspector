import DesignSystem
import SwiftUI

/// File facts under the sidebar's document card. The card names the file, so there is no header;
/// counts the outliner already lists (materials, animations) are left out.
struct FileSection: View {
    var stats: Stats
    var fileName: String

    var body: some View {
        VStack(spacing: DS.Spacing.xs) {
            DSFactRow("Triangles", value: stats.triangleCount.formatted())
            DSFactRow("Textures", value: texturesValue)
            if let size = fileSizeValue {
                DSFactRow("File size", value: size)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("File \(fileName)")
        .padding(.horizontal, DS.Spacing.l)
        .padding(.bottom, DS.Spacing.m)
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
