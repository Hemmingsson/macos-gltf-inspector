import SwiftUI

/// One layer-list row: indent, type glyph, title — sized like a design tool's layer list
/// (`Font.subheadline`, 11 pt).
///
/// A row with children has no separate disclosure column. An empty group keeps a fold chevron in
/// the glyph slot at all times (right when folded, down when open). A typed row (mesh, camera,
/// light, scene) shows its type glyph and swaps to the chevron while the pointer is over the row;
/// clicking the chevron folds or unfolds. Built for a native `List(selection:)`: the row draws no
/// selection of its own, and pass `isSelected` only so the glyph switches to the label colour on
/// the highlight.
struct DSOutlineRow: View {
    private let title: String
    private let role: NodeKind
    /// Overrides `role.systemImage` when set (light subtypes, default scene).
    private let systemImage: String?
    /// Catalog image; wins over the SF Symbol when set (and no swatch).
    private let assetImage: String?
    /// Material ball tint; wins over catalog image and SF Symbol when set.
    private let swatchColor: Color?
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
        systemImage: String? = nil,
        assetImage: String? = nil,
        swatchColor: Color? = nil,
        depth: Int = 0,
        isExpanded: Bool? = nil,
        isSelected: Bool = false,
        badge: DSStatus? = nil,
        onToggle: @escaping () -> Void = {}
    ) {
        self.title = title
        self.role = role
        self.systemImage = systemImage
        self.assetImage = assetImage
        self.swatchColor = swatchColor
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

    /// Empty groups always show the chevron; typed parents only swap to it on hover.
    private var showsFoldChevron: Bool {
        guard isExpanded != nil else { return false }
        return role == .empty || isHovered
    }

    @ViewBuilder
    private var glyphSlot: some View {
        if let isExpanded, showsFoldChevron {
            Button(action: onToggle) {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .foregroundStyle(.primary)
                    .frame(width: side, height: side)
                    .background {
                        if isHovered {
                            Circle().fill(.quaternary)
                        }
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Collapse" : "Expand")
        } else {
            DSTypeIcon(
                role,
                systemImage: systemImage,
                assetImage: assetImage,
                swatchColor: swatchColor,
                isSelected: isSelected,
                font: Font.subheadline
            )
        }
    }
}
