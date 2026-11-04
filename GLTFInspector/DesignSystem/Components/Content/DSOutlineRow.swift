import SwiftUI

/// One layer-list row: indent, type glyph, title — sized like a design tool's layer list
/// (`Font.subheadline`, 11 pt).
///
/// A row with children has no separate disclosure column. Its glyph slot shows the type glyph
/// (a folder for a group) and turns into a chevron while the pointer is over the row; clicking the
/// chevron folds or unfolds. Built for a native `List(selection:)`: the row draws no selection of
/// its own, and pass `isSelected` only so the glyph switches to the label colour on the highlight.
struct DSOutlineRow: View {
    private let title: String
    private let role: NodeKind
    private let depth: Int
    /// `nil` for a leaf; otherwise whether the row's children are showing.
    private let isExpanded: Bool?
    private let isSelected: Bool
    private let badge: DSStatus?
    private let onToggle: () -> Void

    @State private var isHovered = false
    @ScaledMetric(relativeTo: .subheadline) private var indent = DS.Metrics.outlineIndent
    @ScaledMetric(relativeTo: .subheadline) private var side = DS.Metrics.typeIcon

    init(
        _ title: String,
        role: NodeKind,
        depth: Int = 0,
        isExpanded: Bool? = nil,
        isSelected: Bool = false,
        badge: DSStatus? = nil,
        onToggle: @escaping () -> Void = {}
    ) {
        self.title = title
        self.role = role
        self.depth = depth
        self.isExpanded = isExpanded
        self.isSelected = isSelected
        self.badge = badge
        self.onToggle = onToggle
    }

    var body: some View {
        HStack(spacing: DS.Spacing.s) {
            glyphSlot
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            if let badge {
                Image(systemName: badge.systemImage)
                    .font(.subheadline)
                    .foregroundStyle(badge.tint)
                    .accessibilityLabel(badge == .error ? "Has errors" : "Has warnings")
            }
        }
        .padding(.leading, CGFloat(depth) * indent)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: isExpanded == true ? "Collapse" : "Expand") {
            if isExpanded != nil { onToggle() }
        }
    }

    @ViewBuilder
    private var glyphSlot: some View {
        if let isExpanded, isHovered {
            Button(action: onToggle) {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .foregroundStyle(.primary)
                    .frame(width: side, height: side)
                    .background(Circle().fill(.quaternary))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Collapse" : "Expand")
        } else {
            DSTypeIcon(
                role,
                isGroup: isExpanded != nil,
                isSelected: isSelected,
                font: Font.subheadline
            )
        }
    }
}
