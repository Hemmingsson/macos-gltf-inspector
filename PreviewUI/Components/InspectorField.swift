import DesignSystem
import SwiftUI

/// Read-only TRS cell. Prefer `DSVectorRow` for Position / Rotation / Scale; this wraps
/// `DSValueCell` for any leftover boxed value.
public struct InspectorField: View {
    public var text: String

    public var body: some View {
        DSValueCell(text)
    }
}

// MARK: - Previews

#Preview("default") {
    PreviewCanvas(width: DS.Metrics.inspectorWidth) {
        HStack(spacing: DS.Spacing.s) {
            InspectorField(text: "0.00")
            InspectorField(text: "0.50")
            InspectorField(text: "0.00")
        }
        .padding(DS.Spacing.l)
    }
}

#Preview("high contrast") {
    PreviewCanvas(width: DS.Metrics.inspectorWidth) {
        InspectorField(text: "1.00°")
            .padding(DS.Spacing.l)
    }
}
