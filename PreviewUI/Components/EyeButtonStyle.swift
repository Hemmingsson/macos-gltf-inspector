import SwiftUI

/// Outliner visibility toggle: rounded-rect accent focus ring.
public struct EyeButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                PreviewFocusStroke(shape: .roundedRect(4))
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - Previews

#Preview("eye button") {
    Button {} label: {
        Image(systemName: "eye")
            .font(.system(size: 12))
            .foregroundStyle(Theme.text)
            .frame(width: 16, height: 16)
            .contentShape(.rect)
    }
    .buttonStyle(EyeButtonStyle())
    .padding(24)
}
