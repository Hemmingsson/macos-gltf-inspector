import DesignSystem
import SwiftUI

/// The file-name block at the top of the sidebar — `DSDocumentCard` plus an optional
/// material-variant `DSMenuPicker`. Shows the full file name with the file size under it.
///
/// The window has no title band (DESIGN.md: the file name lives in the sidebar), so if this
/// block is missing there is nothing anywhere on screen that says which file you are looking at.
struct DocumentHeader: View {
    var fileName: String
    /// Under the title. A placeholder header (no file yet) passes nil.
    var fileSizeBytes: Int64?
    var variantNames: [String] = []
    var selectedVariantIndex: Int?
    var onSelectVariant: (Int?) -> Void = { _ in }

    var body: some View {
        let subtitle = fileSizeBytes.map {
            ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
        }
        Group {
            if variantNames.isEmpty {
                DSDocumentCard(fileName, subtitle: subtitle)
            } else {
                DSDocumentCard(fileName, subtitle: subtitle) {
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

#Preview("with file size", traits: .fixedLayout(width: 248, height: 88)) {
    PreviewCanvas(width: DS.Metrics.sidebarWidth, height: 88) {
        DocumentHeader(
            fileName: FixtureSceneModel.cube.fileName,
            fileSizeBytes: FixtureSceneModel.cube.fileSizeBytes
        )
    }
}

#Preview("with variants", traits: .fixedLayout(width: 248, height: 116)) {
    PreviewCanvas(width: DS.Metrics.sidebarWidth, height: 116) {
        DocumentHeader(
            fileName: "Variants.glb",
            fileSizeBytes: FixtureSceneModel.cube.fileSizeBytes,
            variantNames: ["Wood", "Metal", "Paint"],
            selectedVariantIndex: 1,
            onSelectVariant: { _ in }
        )
    }
}
