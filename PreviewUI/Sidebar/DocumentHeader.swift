import DesignSystem
import SwiftUI

/// The file-name block at the top of the sidebar — `DSDocumentCard` plus an optional
/// material-variant `DSMenuPicker`. Shows the name without its extension and the file kind under
/// it; clicking it selects the whole model, which opens the document inspector.
///
/// The window has no title band (DESIGN.md: the file name lives in the sidebar), so if this
/// block is missing there is nothing anywhere on screen that says which file you are looking at.
struct DocumentHeader: View {
    var fileName: String
    /// Under the title. Defaults to the file kind; a placeholder header (no file yet) passes nil.
    var subtitle: String?
    var variantNames: [String] = []
    var selectedVariantIndex: Int?
    var onSelectVariant: (Int?) -> Void = { _ in }
    var isSelected = false
    /// Selects the whole model. Nil leaves the card static (no file loaded).
    var onSelect: (() -> Void)?

    init(
        fileName: String,
        subtitle: String? = nil,
        variantNames: [String] = [],
        selectedVariantIndex: Int? = nil,
        onSelectVariant: @escaping (Int?) -> Void = { _ in },
        isSelected: Bool = false,
        onSelect: (() -> Void)? = nil
    ) {
        self.fileName = fileName
        self.subtitle = subtitle
        self.variantNames = variantNames
        self.selectedVariantIndex = selectedVariantIndex
        self.onSelectVariant = onSelectVariant
        self.isSelected = isSelected
        self.onSelect = onSelect
    }

    var body: some View {
        let title = DocumentIdentity.title(fileName)
        Group {
            if variantNames.isEmpty {
                DSDocumentCard(title, subtitle: subtitle, isSelected: isSelected, action: onSelect)
            } else {
                DSDocumentCard(title, subtitle: subtitle, isSelected: isSelected, action: onSelect) {
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

#Preview("with kind", traits: .fixedLayout(width: 248, height: 88)) {
    PreviewCanvas(width: DS.Metrics.sidebarWidth, height: 88) {
        DocumentHeader(
            fileName: FixtureSceneModel.cube.fileName,
            subtitle: DocumentIdentity.kind(FixtureSceneModel.cube.fileName)
        )
    }
}

#Preview("with variants", traits: .fixedLayout(width: 248, height: 116)) {
    PreviewCanvas(width: DS.Metrics.sidebarWidth, height: 116) {
        DocumentHeader(
            fileName: "Variants.glb",
            subtitle: "glTF Binary",
            variantNames: ["Wood", "Metal", "Paint"],
            selectedVariantIndex: 1,
            onSelectVariant: { _ in }
        )
    }
}
