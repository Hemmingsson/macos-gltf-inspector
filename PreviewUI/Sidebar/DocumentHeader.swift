import DesignSystem
import SwiftUI

/// The file-name block at the top of the sidebar — `DSDocumentCard` plus an optional
/// material-variant `DSMenuPicker`. Shows the name without its extension, and the file format
/// under it.
///
/// The window has no title band (DESIGN.md: the file name lives in the sidebar), so if this
/// block is missing there is nothing anywhere on screen that says which file you are looking at.
struct DocumentHeader: View {
    var fileName: String
    var variantNames: [String] = []
    var selectedVariantIndex: Int?
    var onSelectVariant: (Int?) -> Void = { _ in }

    var body: some View {
        let title = DocumentIdentity.title(fileName)
        let subtitle = DocumentIdentity.kind(fileName)
        Group {
            if variantNames.isEmpty {
                DSDocumentCard(title, subtitle: subtitle)
            } else {
                DSDocumentCard(title, subtitle: subtitle) {
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

#Preview("with format", traits: .fixedLayout(width: 248, height: 88)) {
    PreviewCanvas(width: DS.Metrics.sidebarWidth, height: 88) {
        DocumentHeader(fileName: FixtureSceneModel.cube.fileName)
    }
}

#Preview("with variants", traits: .fixedLayout(width: 248, height: 116)) {
    PreviewCanvas(width: DS.Metrics.sidebarWidth, height: 116) {
        DocumentHeader(
            fileName: "Variants.glb",
            variantNames: ["Wood", "Metal", "Paint"],
            selectedVariantIndex: 1,
            onSelectVariant: { _ in }
        )
    }
}
