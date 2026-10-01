import DesignSystem
import SwiftUI

/// Authored (or fitted) TRS grid for the selected node — Position / Rotation / Scale.
public struct TransformSection: View {
    public var transform: TransformInfo
    public var isAuthored: Bool

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InspectorSectionHeader(isAuthored ? "Transform · authored" : "Transform · fitted")

            Grid(alignment: .leading, horizontalSpacing: DS.Spacing.s, verticalSpacing: DS.Spacing.s) {
                GridRow {
                    DSVectorRow(
                        "Position",
                        shortTitle: "P",
                        x: format(transform.position.x),
                        y: format(transform.position.y),
                        z: format(transform.position.z)
                    )
                }
                GridRow {
                    DSVectorRow(
                        "Rotation",
                        shortTitle: "R",
                        x: format(transform.rotationDegrees.x, suffix: "°"),
                        y: format(transform.rotationDegrees.y, suffix: "°"),
                        z: format(transform.rotationDegrees.z, suffix: "°")
                    )
                }
                GridRow {
                    DSVectorRow(
                        "Scale",
                        shortTitle: "S",
                        x: format(transform.scale.x),
                        y: format(transform.scale.y),
                        z: format(transform.scale.z)
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Spacing.l)
            .padding(.top, DS.Spacing.xxs)
            .padding(.bottom, DS.Spacing.m)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isAuthored ? "Transform, authored" : "Transform, fitted")
    }

    private func format(_ value: Double, suffix: String? = nil) -> String {
        let number = String(format: "%.2f", value)
        if let suffix { return number + suffix }
        return number
    }
}

// MARK: - Previews

#Preview("authored") {
    PreviewCanvas(width: DS.Metrics.inspectorWidth) {
        let detail = NodeDetailFixtures.mesh
        TransformSection(
            transform: detail.transform!,
            isAuthored: detail.isTransformAuthored
        )
    }
}

#Preview("fitted") {
    PreviewCanvas(width: DS.Metrics.inspectorWidth) {
        let detail = NodeDetailFixtures.mesh
        TransformSection(
            transform: detail.transform!,
            isAuthored: false
        )
    }
}
