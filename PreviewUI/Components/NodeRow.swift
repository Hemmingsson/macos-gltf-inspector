import DesignSystem
import SwiftUI

/// One outliner row: indent, type glyph (a folder for a group), name. A row with children swaps
/// its glyph for a fold chevron on hover — see `DSOutlineRow`.
///
/// Built for a native `List(selection:)` — the row draws **no** selection of its own.
struct NodeRow: View {
    var item: OutlinerItem
    var isSelected: Bool
    var depth: Int = 0
    /// `nil` for a leaf or a flat (non-folding) section.
    var isExpanded: Bool? = nil
    /// Worst validator finding on this row, when it is a fault. Notes get no badge.
    var badge: DSStatus? = nil
    var onToggle: () -> Void = {}

    private var role: DSTypeRole {
        DSTypeRole(rawValue: item.id.kind.rawValue) ?? .empty
    }

    var body: some View {
        DSOutlineRow(
            item.name,
            role: role,
            depth: depth,
            isExpanded: isExpanded,
            isSelected: isSelected,
            badge: badge,
            onToggle: onToggle
        )
        .accessibilityLabel("\(item.name), \(item.id.kind.displayTitle)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Previews

#Preview("warning badge", traits: .fixedLayout(width: 248, height: 44)) {
    PreviewCanvas(width: DS.Metrics.sidebarWidth, height: 44) {
        NodeRow(
            item: OutlinerItem(id: NodeID(kind: .material, index: 0), name: "DefaultMaterial"),
            isSelected: false,
            badge: .warning
        )
    }
}

#Preview("flat", traits: .fixedLayout(width: 248, height: 44)) {
    PreviewCanvas(width: DS.Metrics.sidebarWidth, height: 44) {
        NodeRow(
            item: OutlinerItem(id: NodeID(kind: .material, index: 0), name: "DefaultMaterial"),
            isSelected: false
        )
    }
}
