import GLTFCore
import SwiftUI

/// Authored TRS of the selected node: Position / Rotation (Euler degrees) / Scale.
struct TransformSection: View {
    var node: GLTFDocument.Node

    var body: some View {
        let rotation = node.rotationDegrees
        VStack(alignment: .leading, spacing: 0) {
            InspectorSectionHeader("Transform · authored")
            Grid(alignment: .leading, horizontalSpacing: DS.Spacing.s, verticalSpacing: DS.Spacing.s) {
                GridRow {
                    DSVectorRow("Position", shortTitle: "P", x: format(node.translation.x),
                                y: format(node.translation.y), z: format(node.translation.z))
                }
                GridRow {
                    DSVectorRow("Rotation", shortTitle: "R", x: format(rotation.x) + "°",
                                y: format(rotation.y) + "°", z: format(rotation.z) + "°")
                }
                GridRow {
                    DSVectorRow("Scale", shortTitle: "S", x: format(node.scale.x),
                                y: format(node.scale.y), z: format(node.scale.z))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Spacing.l)
            .padding(.top, DS.Spacing.xxs)
            .padding(.bottom, DS.Spacing.m)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Transform, authored")
    }

    private func format(_ value: some BinaryFloatingPoint) -> String {
        String(format: "%.2f", Double(value))
    }
}
