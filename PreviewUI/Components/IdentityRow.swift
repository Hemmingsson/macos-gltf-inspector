import DesignSystem
import SwiftUI

/// Selection identity under the Open-in row: glyph, name, and what it is.
struct IdentityRow: View {
    var name: String
    var subtitle: String
    /// Nil draws the document glyph (the whole model is selected).
    var role: DSTypeRole?

    init(name: String, kind: NodeKind) {
        self.name = name
        self.subtitle = kind.displayTitle
        self.role = DSTypeRole(rawValue: kind.rawValue) ?? .empty
    }

    /// The whole model: file name and file kind beside the document glyph.
    init(documentName: String, kind: String) {
        self.name = documentName
        self.subtitle = kind
        self.role = nil
    }

    var body: some View {
        HStack(alignment: .center, spacing: DS.Spacing.m) {
            if let role {
                DSTypeIcon(role)
            } else {
                Image(systemName: "cube")
                    .font(DS.Font.body)
                    .imageScale(.large)
                    .foregroundStyle(DS.Color.accent)
                    .accessibilityHidden(true)
            }

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

// MARK: - Previews

#Preview("mesh") {
    PreviewCanvas(width: DS.Metrics.inspectorWidth) {
        let detail = NodeDetailFixtures.mesh
        IdentityRow(
            name: detail.name,
            kind: detail.kind
        )
    }
}

#Preview("material") {
    PreviewCanvas(width: DS.Metrics.inspectorWidth) {
        let detail = NodeDetailFixtures.material
        IdentityRow(
            name: detail.name,
            kind: detail.kind
        )
    }
}
