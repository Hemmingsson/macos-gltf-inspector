import SwiftUI

/// A compact fact tag — "12 tris", "1 UV set", "Base", "Normal". Lay several out with
/// `DSFlowLayout`.
///
/// `.secondary` text on the quietest vibrant fill (`HierarchicalShapeStyle.quinary`, `.quinary`) at
/// `DS.Radius.small`, so chips stay legible on glass without competing with values. Digits are
/// monospaced so counts in neighbouring chips do not jitter. Not interactive.
struct DSChip: View {
    private let title: String
    private let systemImage: String?

    /// - Parameters:
    ///   - title: Chip text.
    ///   - systemImage: Optional leading SF Symbol.
    init(_ title: String, systemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
            }
            Text(title)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.subheadline.monospacedDigit())
        .foregroundStyle(.secondary)
        .padding(.horizontal, DS.Spacing.m)
        .padding(.vertical, DS.Spacing.xxs)
        .background(.quinary, in: RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous))
    }
}
