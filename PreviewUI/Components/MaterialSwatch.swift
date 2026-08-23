import SwiftUI

/// Small colour tile for material factor readouts and map thumbnails.
public struct MaterialSwatch: View {
    public var color: Color
    public var size: CGFloat

    @Environment(\.previewBorder) private var border

    public init(color: Color, size: CGFloat) {
        self.color = color
        self.size = size
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: max(4, size * 0.18), style: .continuous)
            .fill(color)
            .frame(width: size, height: size)
            .overlay {
                RoundedRectangle(cornerRadius: max(4, size * 0.18), style: .continuous)
                    .strokeBorder(border, lineWidth: Theme.hairlineWidth)
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Previews

#Preview("thumbnail") {
    MaterialSwatch(color: Color(red: 0.82, green: 0.24, blue: 0.18), size: 28)
        .padding(24)
}

#Preview("compact") {
    MaterialSwatch(color: Color(red: 0.82, green: 0.24, blue: 0.18), size: 12)
        .padding(24)
}
