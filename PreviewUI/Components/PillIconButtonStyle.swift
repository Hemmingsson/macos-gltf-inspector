import SwiftUI

/// Fixed 30×30 pill glyph button: inset selection wash + accent focus ring.
public struct PillIconButtonStyle: ButtonStyle {
    public var active: Bool

    public init(active: Bool) {
        self.active = active
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if active {
                    // A contained circle (matching the pane-toggle chrome buttons), not a wide
                    // rounded rect that reads oversized against the pill it sits in.
                    Circle()
                        .fill(Theme.selection)
                        .padding(PillMetrics.toggleWashInset)
                }
            }
            .overlay {
                PreviewFocusStroke(shape: .circle)
            }
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

// MARK: - Previews

#Preview("on") {
    Button {} label: {
        Image(systemName: "star")
            .font(.system(size: PillMetrics.glyphSize))
            .frame(width: PillMetrics.buttonSize, height: PillMetrics.buttonSize)
    }
    .buttonStyle(PillIconButtonStyle(active: true))
    .padding(24)
}

#Preview("off") {
    Button {} label: {
        Image(systemName: "star")
            .font(.system(size: PillMetrics.glyphSize))
            .frame(width: PillMetrics.buttonSize, height: PillMetrics.buttonSize)
    }
    .buttonStyle(PillIconButtonStyle(active: false))
    .padding(24)
}
