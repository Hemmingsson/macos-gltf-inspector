import SwiftUI

/// One outliner row: indent, type glyph (or a permanent fold chevron for an empty group), name.
/// Typed rows with children swap their glyph for a fold chevron on hover — see `DSOutlineRow`.
///
/// Built for a native `List(selection:)` — the row draws **no** selection of its own.
struct NodeRow: View {
    var item: OutlinerItem
    var isJoint: Bool = false
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
    /// Layer visibility for scene-graph rows; nil for every other row.
    var visibility: DSVisibility? = nil
    /// The node is under the canvas pointer: a light tint, never the selection highlight.
    var isPointed: Bool = false
    var onVisibility: (_ solo: Bool) -> Void = { _ in }
    var onToggle: () -> Void = {}
    /// Tree guide flags when the guide-line experiment is on.
    var guides: [Bool]? = nil

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
            isJoint: isJoint,
            badge: badge,
            visibility: visibility,
            onVisibility: onVisibility,
            onToggle: onToggle,
            guides: guides
        )
        .background {
            if isPointed, !isSelected {
                RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
                    .fill(DS.Color.pointedRowFill)
                    .padding(.horizontal, -DS.Spacing.xs)
            }
        }
        .accessibilityLabel("\(item.name), \(kindTitle ?? item.id.kind.displayTitle)")
        .accessibilityIdentifier("outliner-\(item.id.kind.rawValue)-\(item.id.index)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
