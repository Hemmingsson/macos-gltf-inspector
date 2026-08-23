import SwiftUI

/// Selection identity under the action cluster.
public struct IdentityRow: View {
    public var name: String
    public var kindTitle: String
    public var kind: NodeKind

    public var body: some View {
        HStack(alignment: .center, spacing: 9) {
            NodeIcon(kind: kind)

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(kindTitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.text2)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 2)
        .padding(.bottom, 10)
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Previews

#Preview("mesh") {
    PreviewCanvas(width: Theme.inspectorWidth) {
        let detail = NodeDetailFixtures.mesh
        IdentityRow(
            name: detail.name,
            kindTitle: detail.kind.displayTitle,
            kind: detail.kind
        )
    }
}

#Preview("material") {
    PreviewCanvas(width: Theme.inspectorWidth) {
        let detail = NodeDetailFixtures.material
        IdentityRow(
            name: detail.name,
            kindTitle: detail.kind.displayTitle,
            kind: detail.kind
        )
    }
}
