import DesignSystem
import SwiftUI

/// Selection identity under the Open-in row.
struct IdentityRow: View {
    var name: String
    var kindTitle: String
    var kind: NodeKind

    var body: some View {
        HStack(alignment: .center, spacing: DS.Spacing.m) {
            DSTypeIcon(DSTypeRole(rawValue: kind.rawValue) ?? .empty)

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(name)
                    .font(DS.Font.bodyEmphasized)
                    .foregroundStyle(DS.Color.textPrimary)
                    .lineLimit(1)
                Text(kindTitle)
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
            kindTitle: detail.kind.displayTitle,
            kind: detail.kind
        )
    }
}

#Preview("material") {
    PreviewCanvas(width: DS.Metrics.inspectorWidth) {
        let detail = NodeDetailFixtures.material
        IdentityRow(
            name: detail.name,
            kindTitle: detail.kind.displayTitle,
            kind: detail.kind
        )
    }
}
