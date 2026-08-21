import SwiftUI

/// Shared metrics for titlebar chrome icon buttons (sidebar / inspector / screenshot).
///
/// Locked to the same 30 pt hit target as `PillMetrics.buttonSize` so open/closed restore
/// chrome, Stage/Camera toggles, and traffic-light optical center share one size.
enum ChromeMetrics {
    /// Matches `PillMetrics.buttonSize` — one size open or closed, left or right.
    static let buttonSize: CGFloat = 30
    static let glyphSize: CGFloat = 13
    /// Inset of the selected wash from the circle edge (same idea as pill `.tbtn.on`).
    static let selectionInset: CGFloat = 2
    /// Gap between floating restore chrome and the nearest canvas pill.
    /// Keep ≥16 so Liquid Glass does not morph the circle into the Stage / Camera capsule.
    static let pillClearance: CGFloat = 20

    /// Top pad so a `buttonSize` control’s center lands on `Theme.trafficLightCenterY`.
    static var bandTopInset: CGFloat {
        Theme.trafficLightCenterY - buttonSize / 2
    }

    /// Stage pill leading inset when the left sidebar is collapsed (traffic lights + toggle).
    static var collapsedLeadingInset: CGFloat {
        Theme.trafficLightLeadingClearance + buttonSize + pillClearance
    }

    /// Camera pill trailing inset when the inspector is collapsed (screenshot · share · toggle).
    /// Camera is now several islands wide — keep generous clearance past the floating ActionRow.
    static var collapsedTrailingInset: CGFloat {
        // ActionRow ≈ 3×30 + hair + pads; Camera cluster ≈ framing + 3 circles + gaps.
        118 + pillClearance + 200
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
    @Environment(\.previewFlattenGlass) private var flattenGlass
    @Environment(\.previewBorder) private var border

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
        .background { chromeBackground }
        .overlay {
            PreviewFocusStroke(shape: .circle, isFocusedOverride: isFocused)
        }
        // Hard lock: Liquid Glass must not grow past the hit target when selected.
        .frame(width: ChromeMetrics.buttonSize, height: ChromeMetrics.buttonSize)
        .focused($isFocused)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(prominent ? [.isSelected] : [])
    }

    @ViewBuilder
    private var chromeBackground: some View {
        if flattenGlass {
            Circle()
                .fill(prominent ? Theme.selection : Theme.card)
                .overlay {
                    Circle()
                        .strokeBorder(border, lineWidth: Theme.hairlineWidth)
                }
        } else {
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
    }
}
