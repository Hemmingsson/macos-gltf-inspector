import SwiftUI

/// Left-to-right wrapping layout: places subviews in reading order and starts a new line when the
/// next one would overflow the proposed width. Built for `DSChip` rows, but lays out any views.
///
/// There is no per-row count: how many fit depends on the pane width, the text size and the
/// localisation. A subview wider than the whole line gets the line's width (so a long chip
/// truncates instead of overflowing). Lines are top-aligned. SwiftUI mirrors the placement for
/// right-to-left layouts.
public struct DSFlowLayout: Layout {
    private let horizontalSpacing: CGFloat
    private let verticalSpacing: CGFloat

    /// Same gap between items and between lines. Defaults to `DS.Spacing.s`.
    public init(spacing: CGFloat = DS.Spacing.s) {
        self.init(horizontalSpacing: spacing, verticalSpacing: spacing)
    }

    public init(horizontalSpacing: CGFloat, verticalSpacing: CGFloat) {
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let lines = arrange(subviews, maxWidth: proposal.width ?? .infinity)
        let width = lines.map(\.width).max() ?? 0
        let height = lines.map(\.height).reduce(0, +)
            + verticalSpacing * CGFloat(max(lines.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    public func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var y = bounds.minY
        for line in arrange(subviews, maxWidth: bounds.width) {
            var x = bounds.minX
            for item in line.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + horizontalSpacing
            }
            y += line.height + verticalSpacing
        }
    }

    // MARK: Line breaking

    private struct Item {
        var index: Int
        var size: CGSize
    }

    private struct Line {
        var items: [Item] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, maxWidth: CGFloat) -> [Line] {
        var lines: [Line] = []
        var current = Line()

        for index in subviews.indices {
            var size = subviews[index].sizeThatFits(.unspecified)
            if size.width > maxWidth {
                size = subviews[index].sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
                size.width = min(size.width, maxWidth)
            }

            var lineWidth = current.items.isEmpty
                ? size.width
                : current.width + horizontalSpacing + size.width
            if !current.items.isEmpty, lineWidth > maxWidth {
                lines.append(current)
                current = Line()
                lineWidth = size.width
            }

            current.width = lineWidth
            current.height = max(current.height, size.height)
            current.items.append(Item(index: index, size: size))
        }

        if !current.items.isEmpty {
            lines.append(current)
        }
        return lines
    }
}

// MARK: - Previews

#Preview("Flow layout") {
    DSContentPreviewStage {
        DSFlowLayout {
            ForEach(["12 tris", "24 verts", "1 UV set", "Tangents", "Vertex colors", "Skinned", "2 morph targets"], id: \.self) {
                DSChip($0)
            }
        }
        .border(DS.Color.separator)
    }
}

#Preview("Flow layout narrow, dark") {
    DSContentPreviewStage(width: 160) {
        DSFlowLayout(horizontalSpacing: DS.Spacing.xs, verticalSpacing: DS.Spacing.m) {
            DSChip("Base")
            DSChip("Normal")
            DSChip("Metallic-roughness")
            DSChip("Occlusion")
        }
        DSFlowLayout {}
    }
    .preferredColorScheme(.dark)
}
