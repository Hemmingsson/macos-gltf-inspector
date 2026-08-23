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
