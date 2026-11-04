import SwiftUI

/// One outliner row: indent, type glyph (or a permanent fold chevron for an empty group), name.
/// Typed rows with children swap their glyph for a fold chevron on hover — see `DSOutlineRow`.
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
    /// Overrides `item.id.kind.systemImage` (light subtypes, default scene).
    var systemImage: String? = nil
    /// Catalog image (Blender / Spline).
    var assetImage: String? = nil
    /// Material ball tint.
    var swatchColor: Color? = nil
    /// VoiceOver type phrase; defaults to `item.id.kind.displayTitle`.
    var kindTitle: String? = nil
    var onToggle: () -> Void = {}

    private var role: NodeKind {
        item.id.kind
    }

    var body: some View {
        DSOutlineRow(
            item.name,
            role: role,
            systemImage: systemImage,
            assetImage: assetImage,
            swatchColor: swatchColor,
            depth: depth,
            isExpanded: isExpanded,
            isSelected: isSelected,
            badge: badge,
            onToggle: onToggle
        )
        .accessibilityLabel("\(item.name), \(kindTitle ?? item.id.kind.displayTitle)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
