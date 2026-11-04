import DesignSystem
import SwiftUI

/// One outliner row: type icon and name.
///
/// Built for a native `List(selection:)` — the row draws **no** selection of its own.
struct NodeRow: View {
    var item: OutlinerItem
    var isSelected: Bool

    /// Group / folder nodes with children use the chevron as the affordance — no dotted icon.
    private var showsNodeIcon: Bool {
        !(item.id.kind == .empty && item.hasChildren)
    }

    private var role: DSTypeRole {
        DSTypeRole(rawValue: item.id.kind.rawValue) ?? .empty
    }

    var body: some View {
        DSListRow(item.name) { iconSlot }
            .accessibilityLabel("\(item.name), \(item.id.kind.displayTitle)")
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    @ViewBuilder
    private var iconSlot: some View {
        if showsNodeIcon {
            DSTypeIcon(role)
        } else {
            Color.clear
                .frame(width: DS.Metrics.typeIcon, height: DS.Metrics.typeIcon)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Previews

#Preview("flat", traits: .fixedLayout(width: 248, height: 44)) {
    PreviewCanvas(width: DS.Metrics.sidebarWidth, height: 44) {
        NodeRow(
            item: OutlinerItem(id: NodeID(kind: .material, index: 0), name: "DefaultMaterial"),
            isSelected: false
        )
    }
}
