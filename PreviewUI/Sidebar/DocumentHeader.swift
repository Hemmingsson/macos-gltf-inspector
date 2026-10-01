import DesignSystem
import SwiftUI

/// The file-name block at the top of the sidebar — `DSDocumentCard` plus an optional
/// material-variant `DSMenuPicker`.
///
/// The window has no title band (DESIGN.md: the file name lives in the sidebar), so if this
/// block is missing there is nothing anywhere on screen that says which file you are looking at.
public struct DocumentHeader: View {
    public var fileName: String
    /// The scene being shown. Nil for a file with no named scene — the subtitle then collapses
    /// rather than printing a placeholder.
    public var sceneName: String?
    public var variantNames: [String] = []
    public var selectedVariantIndex: Int?
    public var onSelectVariant: (Int?) -> Void = { _ in }

    public var body: some View {
        Group {
            if variantNames.isEmpty {
                DSDocumentCard(fileName, subtitle: sceneName)
            } else {
                DSDocumentCard(fileName, subtitle: sceneName) {
                    DSMenuPicker(
                        "Material variant",
                        selection: Binding(
                            get: { selectedVariantIndex },
                            set: onSelectVariant
                        ),
                        options: [nil] + variantNames.indices.map { Optional($0) },
                        labelVisibility: .hidden
                    ) { $0.map { variantNames[$0] } ?? "Default" }
                    .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, DS.Spacing.paneInset)
        .padding(.vertical, DS.Spacing.m)
    }
}

// MARK: - Previews

#Preview("file only", traits: .fixedLayout(width: 248, height: 72)) {
    PreviewCanvas(width: DS.Metrics.sidebarWidth, height: 72) {
        DocumentHeader(fileName: FixtureSceneModel.cube.fileName)
    }
}

#Preview("with scene", traits: .fixedLayout(width: 248, height: 88)) {
    PreviewCanvas(width: DS.Metrics.sidebarWidth, height: 88) {
        DocumentHeader(
            fileName: FixtureSceneModel.cube.fileName,
            sceneName: FixtureSceneModel.cube.scenes.first?.name
        )
    }
}

#Preview("with variants", traits: .fixedLayout(width: 248, height: 116)) {
    PreviewCanvas(width: DS.Metrics.sidebarWidth, height: 116) {
        DocumentHeader(
            fileName: "Variants.glb",
            sceneName: "Scene",
            variantNames: ["Wood", "Metal", "Paint"],
            selectedVariantIndex: 1,
            onSelectVariant: { _ in }
        )
    }
}
