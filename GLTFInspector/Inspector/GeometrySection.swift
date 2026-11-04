import GLTFCore
import SwiftUI

/// The selected mesh node's geometry facts; attributes appear only when present.
struct GeometrySection: View {
    var node: GLTFDocument.Node

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InspectorSectionHeader("Geometry")
            FlexibleChipRow(items: chips)
                .padding(.horizontal, DS.Spacing.l)
                .padding(.top, DS.Spacing.xxs)
                .padding(.bottom, DS.Spacing.m)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Geometry: \(chips.joined(separator: ", "))")
    }

    private var chips: [String] {
        var items = ["\(node.triangleCount.formatted()) tris", "\(node.vertexCount.formatted()) verts"]
        if node.uvSetCount > 0 {
            items.append(node.uvSetCount == 1 ? "1 UV set" : "\(node.uvSetCount) UV sets")
        }
        if node.hasTangents { items.append("Tangents") }
        if node.hasVertexColors { items.append("Vertex colors") }
        if let count = node.gpuInstanceCount, count > 1 {
            items.append("× \(count.formatted()) instances")
        }
        return items
    }
}
