import SwiftUI

/// Per-node geometry chips — only facts that exist (DESIGN.md: hide what the node lacks).
struct GeometrySection: View {
    var geometry: GeometryInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InspectorSectionHeader(title: "Geometry")

            FlexibleChipRow(items: chips, chipsPerRow: 3)
                .padding(.horizontal, 14)
                .padding(.top, 2)
                .padding(.bottom, 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Geometry: \(chips.joined(separator: ", "))")
    }

    private var chips: [String] {
        // Main-html shows tris / verts / UV only. Extra authored attributes appear when present
        // so a missing-tangents warning in Validation still has a geometry counterpart.
        var items = [
            "\(geometry.triangleCount.formatted()) tris",
            "\(geometry.vertexCount.formatted()) verts"
        ]
        if geometry.uvSetCount > 0 {
            items.append(geometry.uvSetCount == 1 ? "1 UV set" : "\(geometry.uvSetCount) UV sets")
        }
        if geometry.hasTangents { items.append("Tangents") }
        if geometry.hasVertexColors { items.append("Vertex colors") }
        return items
    }
}
