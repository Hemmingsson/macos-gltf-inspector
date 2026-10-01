import SwiftUI

/// A compact fact tag — "12 tris", "1 UV set", "Base", "Normal". Lay several out with
/// `DSFlowLayout`.
///
/// `.secondary` text on the quietest vibrant fill (`DS.Color.cardFill`, `.quinary`) at
/// `DS.Radius.small`, so chips stay legible on glass without competing with values. Digits are
/// monospaced so counts in neighbouring chips do not jitter. Not interactive.
public struct DSChip: View {
    private let title: String
    private let systemImage: String?

    /// - Parameters:
    ///   - title: Chip text.
    ///   - systemImage: Optional leading SF Symbol.
    public init(_ title: String, systemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
    }

    public var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
            }
            Text(title)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(DS.Font.subheadline.monospacedDigit())
        .foregroundStyle(DS.Color.textSecondary)
        .padding(.horizontal, DS.Spacing.m)
        .padding(.vertical, DS.Spacing.xxs)
        .background(DS.Color.cardFill, in: RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous))
    }
}

// MARK: - Previews

#Preview("Chip") {
    DSContentPreviewStage {
        DSFlowLayout {
            DSChip("12 tris")
            DSChip("24 verts")
            DSChip("1 UV set")
            DSChip("Tangents")
            DSChip("Vertex colors")
            DSChip("Base", systemImage: "photo")
        }
    }
}

#Preview("Chip long text, dark") {
    DSContentPreviewStage {
        DSFlowLayout {
            DSChip("KHR_materials_clearcoat_extension_with_a_very_long_name")
            DSChip("")
            DSChip("Normal")
        }
    }
    .preferredColorScheme(.dark)
}
