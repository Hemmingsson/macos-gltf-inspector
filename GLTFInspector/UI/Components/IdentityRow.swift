import SwiftUI

/// Selection identity under the Open-in row: glyph, name, and what it is.
struct IdentityRow: View {
    var name: String
    var subtitle: String
    var role: NodeKind

    init(name: String, kind: NodeKind) {
        self.name = name
        self.subtitle = kind.displayTitle
        self.role = kind
    }

    var body: some View {
        HStack(alignment: .center, spacing: DS.Spacing.m) {
            DSTypeIcon(role)

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(name)
                    .font(DS.Font.bodyEmphasized)
                    .foregroundStyle(DS.Color.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(DS.Font.subheadline)
                    .foregroundStyle(DS.Color.textSecondary)
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
