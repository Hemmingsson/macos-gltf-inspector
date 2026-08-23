import SwiftUI

/// Label · value row shared by File / Material / extras facts.
public struct InspectorFactRow: View {
    public var label: String
    public var value: String

    public var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text2)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(Theme.textValue)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Previews

#Preview("short") {
    PreviewCanvas(width: Theme.inspectorWidth) {
        InspectorFactRow(label: "Triangles", value: "12")
            .padding(.horizontal, 14)
    }
}

#Preview("long value") {
    PreviewCanvas(width: Theme.inspectorWidth) {
        InspectorFactRow(label: "Used by", value: "Cube, Sphere, Cylinder, Cone")
            .padding(.horizontal, 14)
    }
}
