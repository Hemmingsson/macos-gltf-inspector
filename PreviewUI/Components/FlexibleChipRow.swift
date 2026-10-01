import DesignSystem
import SwiftUI

/// Left-to-right wrap of chips. How many fit depends on the pane width — there is no
/// `chipsPerRow`.
public struct FlexibleChipRow: View {
    public var items: [String]

    public var body: some View {
        DSFlowLayout {
            ForEach(items, id: \.self) { title in
                DSChip(title)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Previews

#Preview("wrap ideal") {
    PreviewCanvas(width: DS.Metrics.inspectorWidth) {
        FlexibleChipRow(
            items: ["12 tris", "24 verts", "1 UV set", "Tangents", "Vertex colors"]
        )
        .padding(.horizontal, DS.Spacing.l)
    }
}

#Preview("wrap minimum") {
    PreviewCanvas(width: DS.Metrics.inspectorWidthRange.lowerBound) {
        FlexibleChipRow(
            items: ["12 tris", "24 verts", "1 UV set", "Tangents", "Vertex colors"]
        )
        .padding(.horizontal, DS.Spacing.l)
    }
}

#Preview("wrap maximum") {
    PreviewCanvas(width: DS.Metrics.inspectorWidthRange.upperBound) {
        FlexibleChipRow(
            items: ["12 tris", "24 verts", "1 UV set", "Tangents", "Vertex colors"]
        )
        .padding(.horizontal, DS.Spacing.l)
    }
}
