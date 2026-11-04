import GLTFCore
import SwiftUI

/// Geometry totals as chips: the whole scene (no selection) or a group's subtree.
struct TotalsSection: View {
    var title: String
    var totals: GLTFGeometryTotals
    /// Scene-only facts: textures bound by materials and the file's size on disk.
    var textureCount: Int?
    var fileBytes: Int64?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InspectorSectionHeader(title)
            FlexibleChipRow(items: chips)
                .padding(.horizontal, DS.Spacing.l)
                .padding(.top, DS.Spacing.xxs)
                .padding(.bottom, DS.Spacing.m)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(chips.joined(separator: ", "))")
    }

    var chips: [String] {
        var items = [
            "\(totals.triangleCount.formatted()) tris",
            "\(totals.vertexCount.formatted()) verts",
            Self.count(totals.nodeCount, "node"),
            Self.count(totals.meshNodeCount, "mesh"),
        ]
        if totals.uniqueMeshCount != totals.meshNodeCount {
            items.append(Self.count(totals.uniqueMeshCount, "unique mesh", plural: "unique meshes"))
        }
        items.append(Self.count(totals.drawCallCount, "draw call"))
        items.append(Self.count(totals.materialCount, "material"))
        if let textureCount { items.append(Self.count(textureCount, "texture")) }
        if let fileBytes, fileBytes >= 0 {
            items.append(ByteCountFormatter.string(fromByteCount: fileBytes, countStyle: .file))
        }
        return items
    }

    private static func count(_ value: Int, _ singular: String, plural: String? = nil) -> String {
        "\(value.formatted()) \(value == 1 ? singular : plural ?? singular + (singular.hasSuffix("sh") ? "es" : "s"))"
    }
}
