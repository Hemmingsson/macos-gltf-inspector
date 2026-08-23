import SwiftUI

/// Shared metrics for titlebar chrome icon buttons (sidebar / inspector / document actions).
///
/// Locked to `Theme.chromeControlSize` so open/closed restore chrome and Stage/Camera toggles
/// share one size.
public enum ChromeMetrics {
    /// Same hit target as pill toggles — `Theme.chromeControlSize`.
    public static var buttonSize: CGFloat { Theme.chromeControlSize }
    public static let glyphSize: CGFloat = 13
    /// Inset of the selected wash from the circle edge (same idea as pill `.tbtn.on`).
    public static let selectionInset: CGFloat = 2
    /// Gap between floating restore chrome and the nearest canvas island.
    public static let pillClearance: CGFloat = 20

    /// Top pad so a `buttonSize` control’s center lands on `Theme.trafficLightCenterY`.
    public static var bandTopInset: CGFloat {
        Theme.trafficLightCenterY - buttonSize / 2
    }

    /// Stage leading inset when the sidebar is collapsed (lights + toggle + clearance).
    public static var collapsedLeadingInset: CGFloat {
        Theme.trafficLightLeadingClearance + buttonSize + pillClearance
    }

    /// Trailing inset when the inspector is collapsed — clears the floating ActionRow only.
    public static var collapsedTrailingInset: CGFloat {
        floatingActionRowWidth + pillClearance
    }

    /// Intrinsic width of `ActionRow`’s trailing cluster (1 circle + pads).
    public static var floatingActionRowWidth: CGFloat {
        buttonSize + 12 + 12
    }
}

public extension View {
    /// Places content in the unified top chrome band with its vertical center on the
    /// system traffic-light centerline (not the geometric mid of a tall band).
    func chromeBandAligned() -> some View {
        self
            .padding(.top, ChromeMetrics.bandTopInset)
            .frame(height: Theme.topChromeHeight, alignment: .top)
    }
}

/// Circular glass chrome control — fixed 30×30, Sketch / Calendar scale.
///
/// Size never changes with `prominent` or open/closed. Selected = inset selection wash +
/// glyph tint, never `.glassProminent` (that inflated into a huge blue disc).
public struct ChromeIconButton: View {
    public var symbol: String
    public var title: String
    public var prominent: Bool
    public var action: () -> Void

    @FocusState private var isFocused: Bool

    public init(
        symbol: String,
        title: String,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) {
        self.symbol = symbol
        self.title = title
        self.prominent = prominent
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: ChromeMetrics.glyphSize, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(prominent ? Theme.selectionText : Theme.glyph)
                .frame(width: ChromeMetrics.buttonSize, height: ChromeMetrics.buttonSize)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .background {
            Circle()
                .fill(.clear)
                .frame(width: ChromeMetrics.buttonSize, height: ChromeMetrics.buttonSize)
                .glassEffect(.regular.interactive(), in: .circle)
                .overlay {
                    if prominent {
                        Circle()
                            .fill(Theme.selection.opacity(0.28))
                            .padding(ChromeMetrics.selectionInset)
                    }
                }
        }
        .overlay {
            PreviewFocusStroke(shape: .circle, isFocusedOverride: isFocused)
        }
        .frame(width: ChromeMetrics.buttonSize, height: ChromeMetrics.buttonSize)
        .focused($isFocused)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(prominent ? [.isSelected] : [])
    }
}

// MARK: - Previews

#Preview("default") {
    ChromeIconButton(symbol: "sidebar.leading", title: "Show Sidebar") {}
        .padding(24)
}

#Preview("selected") {
    ChromeIconButton(symbol: "sidebar.leading", title: "Hide Sidebar", prominent: true) {}
        .padding(24)
}
