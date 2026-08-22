import SwiftUI

/// Shared metrics for titlebar chrome icon buttons (sidebar / inspector / screenshot).
///
/// Locked to `Theme.chromeControlSize` so open/closed restore chrome and Stage/Camera toggles
/// share one size.
enum ChromeMetrics {
    /// Same hit target as pill toggles — `Theme.chromeControlSize`.
    static var buttonSize: CGFloat { Theme.chromeControlSize }
    static let glyphSize: CGFloat = 13
    /// Inset of the selected wash from the circle edge (same idea as pill `.tbtn.on`).
    static let selectionInset: CGFloat = 2
    /// Gap between floating restore chrome and the nearest canvas island.
    static let pillClearance: CGFloat = 20

    /// Top pad so a `buttonSize` control’s center lands on `Theme.trafficLightCenterY`.
    static var bandTopInset: CGFloat {
        Theme.trafficLightCenterY - buttonSize / 2
    }

    /// Stage leading inset when the sidebar is collapsed (lights + toggle + clearance).
    static var collapsedLeadingInset: CGFloat {
        Theme.trafficLightLeadingClearance + buttonSize + pillClearance
    }

    /// Trailing inset when the inspector is collapsed — clears the floating ActionRow only.
    static var collapsedTrailingInset: CGFloat {
        floatingActionRowWidth + pillClearance
    }

    /// Intrinsic width of `ActionRow`’s trailing cluster (3 circles + hair + pads).
    static var floatingActionRowWidth: CGFloat {
        buttonSize * 3 + 4 * 2 + Theme.hairlineWidth + 4 + 14 + 12
    }
}

extension View {
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
struct ChromeIconButton: View {
    var symbol: String
    var title: String
    var prominent: Bool
    var action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
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
