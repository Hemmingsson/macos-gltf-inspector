import SwiftUI

/// Compact chip used for geometry facts and present material maps (`.chip`).
public struct InspectorChip: View {
    public var title: String

    public var body: some View {
        Text(title)
            .font(.system(size: 11))
            .foregroundStyle(Color.dynamic(light: 0x5B5B60, dark: 0xB0B0B6))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.dynamic(light: 0xEDEEF1, dark: 0x2B2B2E))
            )
    }
}

// MARK: - Previews

#Preview("default") {
    PreviewCanvas(width: Theme.inspectorWidth) {
        InspectorChip(title: "12 tris")
            .padding(14)
    }
}
