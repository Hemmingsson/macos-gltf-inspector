import SwiftUI

/// Top of the right column: Open in on the unified chrome baseline, identity on the row below.
///
/// Sketch / DESIGN.md: Open in… shares the window's top band with the sidebar toggle and canvas
/// pills; selection name sits under that cluster, not beside it.
public struct NodeHeader: View {
    public var name: String
    public var kindTitle: String
    public var kind: NodeKind
    public let openInMenu: AnyView

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ActionRow(openInMenu: openInMenu)

            IdentityRow(name: name, kindTitle: kindTitle, kind: kind)
        }
        .accessibilityElement(children: .contain)
    }
}

/// Action cluster on the unified chrome baseline (`chromeBandAligned()`).
///
/// Document actions (Open in…) trail. When floating over the canvas (inspector closed), the same
/// cluster sits at the trailing edge.
public struct ActionRow: View {
    public let openInMenu: AnyView

    public var body: some View {
        HStack(spacing: 4) {
            Spacer(minLength: 0)
            openInMenu
        }
        .frame(height: ChromeMetrics.buttonSize, alignment: .trailing)
        .padding(.leading, 12)
        .padding(.trailing, 12)
        .chromeBandAligned()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Inspector actions")
    }

}

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
