import SwiftUI

/// Selection identity under the Open-in row: glyph, name, and what it is.
struct IdentityRow: View {
    var name: String
    var subtitle: String
    var role: NodeKind
    var systemImage: String?
    var assetImage: String?
    var swatchColor: Color?

    init(
        name: String,
        kind: NodeKind,
        systemImage: String? = nil,
        assetImage: String? = nil,
        swatchColor: Color? = nil,
        subtitle: String? = nil
    ) {
        self.name = name
        self.subtitle = subtitle ?? kind.displayTitle
        self.role = kind
        self.systemImage = systemImage
        self.assetImage = assetImage
        self.swatchColor = swatchColor
    }

    var body: some View {
        HStack(alignment: .center, spacing: DS.Spacing.m) {
            DSTypeIcon(role, systemImage: systemImage, assetImage: assetImage, swatchColor: swatchColor)

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, DS.Spacing.xxs)
        .padding(.bottom, DS.Spacing.l)
        .padding(.leading, DS.Spacing.l)
        .padding(.trailing, DS.Spacing.l)
        .accessibilityElement(children: .combine)
    }
}
