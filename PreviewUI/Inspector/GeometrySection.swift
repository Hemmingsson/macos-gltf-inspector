import SwiftUI

/// Per-node geometry chips — only facts that exist (DESIGN.md: hide what the node lacks).
public struct GeometrySection: View {
    public var geometry: GeometryInfo

    public var body: some View {
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
        // Tris / verts / UV always; extra authored attributes appear only when present, so a
        // missing-tangents warning in Validation still has a geometry counterpart.
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

// MARK: - Previews

#Preview("basic") {
    PreviewCanvas(width: Theme.inspectorWidth) {
        let detail = NodeDetailFixtures.mesh
        GeometrySection(geometry: detail.geometry!)
    }
}

#Preview("full") {
    PreviewCanvas(width: Theme.inspectorWidth) {
        GeometrySection(
            geometry: GeometryInfo(
                triangleCount: 18_240,
                vertexCount: 21_600,
                uvSetCount: 2,
                hasNormals: true,
                hasTangents: true,
                hasVertexColors: true
            )
        )
    }
}
