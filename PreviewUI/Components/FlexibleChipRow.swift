import SwiftUI

/// Left-to-right wrap of chips. `chipsPerRow` matches inspector width (geometry ≈3, maps ≈4).
public struct FlexibleChipRow: View {
    public var items: [String]
    public var chipsPerRow: Int = 4

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { title in
                        InspectorChip(title: title)
                    }
                }
            }
        }
    }

    private var rows: [[String]] {
        let step = max(chipsPerRow, 1)
        return stride(from: 0, to: items.count, by: step).map { start in
            Array(items[start..<min(start + step, items.count)])
        }
    }
}

// MARK: - Previews

#Preview("wrap") {
    PreviewCanvas(width: Theme.inspectorWidth) {
        FlexibleChipRow(
            items: ["12 tris", "24 verts", "1 UV set", "Tangents", "Vertex colors"],
            chipsPerRow: 3
        )
        .padding(.horizontal, 14)
    }
}
