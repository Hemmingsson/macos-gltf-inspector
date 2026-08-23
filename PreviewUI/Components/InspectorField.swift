import SwiftUI

/// Read-only TRS cell (`.field`). Not editable — this is a viewer, not an editor.
public struct InspectorField: View {
    public var text: String
    @Environment(\.previewBorder) private var border

    public var body: some View {
        Text(text)
            .font(.system(size: 12).monospacedDigit())
            .foregroundStyle(Theme.text)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.card)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(border, lineWidth: Theme.hairlineWidth)
            }
    }
}

// MARK: - Previews

#Preview("default") {
    PreviewCanvas(width: Theme.inspectorWidth) {
        HStack(spacing: 6) {
            InspectorField(text: "0.00")
            InspectorField(text: "0.50")
            InspectorField(text: "0.00")
        }
        .padding(14)
    }
}

#Preview("high contrast") {
    PreviewCanvas(width: Theme.inspectorWidth) {
        InspectorField(text: "1.00°")
            .padding(14)
            .environment(\.previewBorder, Theme.border(contrast: .increased))
    }
}
