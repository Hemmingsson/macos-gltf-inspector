import SwiftUI

/// Authored (or fitted) TRS grid for the selected node — Position / Rotation / Scale.
struct TransformSection: View {
    var transform: TransformInfo
    var isAuthored: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InspectorSectionHeader(
                title: isAuthored ? "Transform · authored" : "Transform · fitted"
            )

            VStack(alignment: .leading, spacing: 6) {
                axisRow(label: "P", values: transform.position, suffix: nil)
                axisRow(label: "R", values: transform.rotationDegrees, suffix: "°")
                axisRow(label: "S", values: transform.scale, suffix: nil)
            }
            .padding(.horizontal, 14)
            .padding(.top, 2)
            .padding(.bottom, 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isAuthored ? "Transform, authored" : "Transform, fitted")
    }

    private func axisRow(label: String, values: Vector3, suffix: String?) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.text2)
                .frame(width: 16, alignment: .leading)
                .accessibilityHidden(true)

            InspectorField(text: format(values.x, suffix: suffix))
            InspectorField(text: format(values.y, suffix: suffix))
            InspectorField(text: format(values.z, suffix: suffix))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(format(values.x, suffix: suffix)), \(format(values.y, suffix: suffix)), \(format(values.z, suffix: suffix))")
    }

    private func format(_ value: Double, suffix: String?) -> String {
        let number = String(format: "%.2f", value)
        if let suffix { return number + suffix }
        return number
    }
}
