import SwiftUI

/// Stage backdrop swatch: circular accent focus ring sized to the swatch.
public struct BackdropSwatchButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                PreviewFocusStroke(shape: .circle)
                    .frame(width: PillMetrics.swatchSize + 6, height: PillMetrics.swatchSize + 6)
            }
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

// MARK: - Previews

#Preview("backdrop swatch") {
    Button {} label: {
        Circle()
            .fill(Theme.backdropWhite)
            .frame(width: PillMetrics.swatchSize, height: PillMetrics.swatchSize)
            .contentShape(.circle)
    }
    .buttonStyle(BackdropSwatchButtonStyle())
    .padding(24)
}
