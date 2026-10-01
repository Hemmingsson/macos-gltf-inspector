import DesignSystem
import SwiftUI

/// Top of the inspector: Open-in as a glass-circle menu at the top right, identity under it.
///
/// Toolbar placement is not used here (needs the shell). `openInMenu` is menu items; `ActionRow`
/// wraps them in `DSGlassMenuButton`.
public struct NodeHeader: View {
    public var name: String
    public var kindTitle: String
    public var kind: NodeKind
    public let openInMenu: AnyView

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ActionRow(openInMenu: openInMenu, alignsToChromeBand: false)

            IdentityRow(name: name, kindTitle: kindTitle, kind: kind)
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Previews

private struct PreviewOpenInItems: View {
    var body: some View {
        Button("Finder") {}
        Button("Blender") {}
    }
}

#Preview("mesh") {
    PreviewCanvas(width: DS.Metrics.inspectorWidth) {
        let detail = NodeDetailFixtures.mesh
        NodeHeader(
            name: detail.name,
            kindTitle: detail.kind.displayTitle,
            kind: detail.kind,
            openInMenu: AnyView(PreviewOpenInItems())
        )
    }
}

#Preview("material") {
    PreviewCanvas(width: DS.Metrics.inspectorWidth) {
        let detail = NodeDetailFixtures.material
        NodeHeader(
            name: detail.name,
            kindTitle: detail.kind.displayTitle,
            kind: detail.kind,
            openInMenu: AnyView(PreviewOpenInItems())
        )
    }
}
