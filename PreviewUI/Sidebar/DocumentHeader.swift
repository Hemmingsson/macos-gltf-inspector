import SwiftUI

/// The file-name block at the top of the sidebar.
///
/// This is where the document identifies itself. The window has no title band (DESIGN.md: the
/// file name lives in the sidebar), so if this block is missing there is nothing anywhere on
/// screen that says which file you are looking at.
struct DocumentHeader: View {
    var fileName: String
    /// The scene being shown. Nil for a file with no named scene — the subtitle then collapses
    /// rather than printing a placeholder.
    var sceneName: String?
    var variantNames: [String] = []
    var selectedVariantIndex: Int?
    var onSelectVariant: (Int?) -> Void = { _ in }

    @Environment(\.previewHair) private var hair

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 9) {
            // Accent, not a type tint: this is the document itself, not a row in the outliner.
            Image(systemName: "cube")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(fileName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let sceneName {
                    Text(sceneName)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.text2)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }

        if !variantNames.isEmpty {
            Picker(
                "Variant",
                selection: Binding(
                    get: { selectedVariantIndex },
                    set: onSelectVariant
                )
            ) {
                Text("Default").tag(Optional<Int>.none)
                ForEach(Array(variantNames.enumerated()), id: \.offset) { index, name in
                    Text(name).tag(Optional(index))
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .accessibilityLabel("Material variant")
        }
        }
        // `padding: 7px 10px; border-radius: 8px; background: #fff; border: 1px solid var(--hair)`
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .background(Theme.card, in: .rect(cornerRadius: 8))
        // `strokeBorder`, not `stroke`: a stroke straddles the edge and would spill half its
        // width outside the 8 pt corner.
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(hair, lineWidth: Theme.hairlineWidth))
        // The card's own inset from the column (`padding: 0 10px 8px` on its container).
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
    }
}
