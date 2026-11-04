import AppKit
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
    private let isJoint: Bool
    private let badge: DSStatus?
    /// Active animation clips target this scene-graph node.
    private let showsAnimatedIndicator: Bool
    private let visibility: DSVisibility?
    private let onVisibility: (_ solo: Bool) -> Void
    private let onToggle: () -> Void
    /// Indent guide lines (`OutlinerTree.Row.guides`); nil draws plain indent.
    private let guides: [Bool]?

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
        isJoint: Bool = false,
        badge: DSStatus? = nil,
        showsAnimatedIndicator: Bool = false,
        visibility: DSVisibility? = nil,
        onVisibility: @escaping (_ solo: Bool) -> Void = { _ in },
        onToggle: @escaping () -> Void = {},
        guides: [Bool]? = nil
    ) {
        self.guides = guides
        self.title = title
        self.role = role
        self.systemImage = systemImage
        self.assetImage = assetImage
        self.swatchColor = swatchColor
        self.depth = depth
        self.isExpanded = isExpanded
        self.isSelected = isSelected
        self.isJoint = isJoint
        self.badge = badge
        self.showsAnimatedIndicator = showsAnimatedIndicator
        self.visibility = visibility
        self.onVisibility = onVisibility
        self.onToggle = onToggle
    }

    var body: some View {
        HStack(spacing: DS.Spacing.s) {
            glyphSlot
            Text(title)
                .font(.subheadline)
                .foregroundStyle(isDimmed ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            if let badge {
                Image(systemName: badge.systemImage)
                    .font(.subheadline)
                    .foregroundStyle(badge.tint)
                    .accessibilityLabel(badge == .error ? "Has errors" : "Has warnings")
            }
            if showsAnimatedIndicator {
                Image(systemName: "figure.walk.motion")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(DS.Color.Role.animation)
                    .accessibilityLabel("Animated")
            }
            visibilityControl
        }
        .padding(.leading, CGFloat(depth) * indent)
        .background(alignment: .leading) {
            if let guides, depth > 0 {
                DSOutlineGuides(guides: guides, indent: indent, glyph: side)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .modifier(OutlineRowAccessibilityActions(
            isExpanded: isExpanded,
            isToggleable: isToggleable,
            visibility: visibility,
            onToggle: onToggle,
            onVisibility: { onVisibility(false) }
        ))
    }

    /// Only the window's own state toggles; inherited and authored states are read-only.
    private var isToggleable: Bool { visibility == .visible || visibility == .hidden }

    private var isDimmed: Bool {
        guard let visibility else { return false }
        return visibility != .visible
    }

    /// Reserves the trailing eye slot whenever `visibility` is set; fades out when visible and not hovered.
    @ViewBuilder
    private var visibilityControl: some View {
        if let visibility {
            Group {
                if visibility == .hiddenInFile {
                    Image(systemName: "eye.slash")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .help("Hidden in the file (KHR_node_visibility)")
                        .accessibilityLabel("Hidden in file")
                } else if visibility == .hiddenByParent {
                    Image(systemName: "eye.slash")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .help("Hidden by a parent layer or by solo")
                        .accessibilityLabel("Hidden by parent")
                } else {
                    Button {
                        // Option-click solos the node; a plain click toggles it.
                        let solo = NSApp.currentEvent?.modifierFlags.contains(.option) ?? false
                        onVisibility(solo)
                    } label: {
                        Image(systemName: visibility == .visible ? "eye" : "eye.slash")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(visibility == .visible ? "Hide (Option-click to solo)" : "Show (Option-click to solo)")
                    .accessibilityLabel(visibility == .visible ? "Hide" : "Show")
                }
            }
            .opacity(visibility == .visible && !isHovered ? 0 : 1)
            .allowsHitTesting(visibility != .visible || isHovered)
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
                // A skin joint is an empty node with its own glyph.
                systemImage: isJoint && role == .empty ? "circle.grid.cross" : systemImage,
                assetImage: assetImage,
                swatchColor: swatchColor,
                isSelected: isSelected,
                font: Font.subheadline
            )
        }
    }
}

private struct OutlineRowAccessibilityActions: ViewModifier {
    let isExpanded: Bool?
    let isToggleable: Bool
    let visibility: DSVisibility?
    let onToggle: () -> Void
    let onVisibility: () -> Void

    func body(content: Content) -> some View {
        if let isExpanded {
            if isToggleable, let visibility {
                content
                    .accessibilityAction(named: isExpanded ? "Collapse" : "Expand", onToggle)
                    .accessibilityAction(named: visibility == .visible ? "Hide" : "Show", onVisibility)
            } else {
                content
                    .accessibilityAction(named: isExpanded ? "Collapse" : "Expand", onToggle)
            }
        } else if isToggleable, let visibility {
            content
                .accessibilityAction(named: visibility == .visible ? "Hide" : "Show", onVisibility)
        } else {
            content
        }
    }
}

/// Hairline tree guides in a row's indent: a vertical line per ancestor level that continues
/// below, and an elbow (└ or ├) from the parent's glyph centre to this row's glyph.
private struct DSOutlineGuides: View {
    let guides: [Bool]
    let indent: CGFloat
    let glyph: CGFloat
    /// List rows sit apart; the lines reach past the row so they join across the gap.
    private let overhang = DS.Spacing.s

    var body: some View {
        Canvas { context, size in
            let top: CGFloat = 0, bottom = size.height, middle = size.height / 2
            var path = Path()
            for (level, continues) in guides.enumerated() {
                let x = (CGFloat(level) * indent + glyph / 2).rounded() + 0.5
                let isOwnLevel = level == guides.count - 1
                if isOwnLevel {
                    path.move(to: CGPoint(x: x, y: top))
                    path.addLine(to: CGPoint(x: x, y: continues ? bottom : middle))
                    path.move(to: CGPoint(x: x, y: middle))
                    path.addLine(to: CGPoint(x: x + indent - glyph / 2 - DS.Spacing.xxs, y: middle))
                } else if continues {
                    path.move(to: CGPoint(x: x, y: top))
                    path.addLine(to: CGPoint(x: x, y: bottom))
                }
            }
            context.stroke(path, with: .color(DS.Color.separator), lineWidth: DS.Metrics.hairline)
        }
        .frame(width: CGFloat(guides.count) * indent)
        .padding(.vertical, -overhang)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
