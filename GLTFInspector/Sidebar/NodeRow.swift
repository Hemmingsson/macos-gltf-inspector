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

    private var role: NodeKind {
        item.id.kind
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
