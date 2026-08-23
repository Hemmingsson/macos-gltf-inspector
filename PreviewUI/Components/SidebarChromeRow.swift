import SwiftUI

/// `sidebar.leading` toggle on the unified chrome band.
///
/// Two placements: **in-sidebar** (`trailingAligned`) sits at the pane's inner (right) edge, by the
/// canvas divider — the traffic lights own the pane's outer/left side; **floating restore** (sidebar
/// collapsed, over the canvas) sits at the leading edge, clearing the three system lights.
public struct SidebarChromeRow: View {
    public var isSidebarVisible: Bool
    public var trailingAligned: Bool = false
    public var onToggleSidebar: () -> Void

    public var body: some View {
        HStack(spacing: 8) {
            if trailingAligned {
                Spacer(minLength: 0)
                toggle
            } else {
                Color.clear
                    .frame(width: Theme.trafficLightLeadingClearance, height: ChromeMetrics.buttonSize)
                toggle
                Spacer(minLength: 0)
            }
        }
        .frame(height: ChromeMetrics.buttonSize, alignment: trailingAligned ? .trailing : .leading)
        .padding(.trailing, trailingAligned ? 12 : 10)
        .chromeBandAligned()
        .accessibilityElement(children: .contain)
    }

    private var toggle: some View {
        ChromeIconButton(
            symbol: "sidebar.leading",
            title: isSidebarVisible ? "Hide Sidebar" : "Show Sidebar",
            prominent: isSidebarVisible,
            action: onToggleSidebar
        )
    }
}

// MARK: - Previews

#Preview("in sidebar visible") {
    PreviewCanvas(width: PreviewCanvas.sidebarWidth) {
        SidebarChromeRow(isSidebarVisible: true, trailingAligned: true) {}
    }
}

#Preview("in sidebar hidden") {
    PreviewCanvas(width: PreviewCanvas.sidebarWidth) {
        SidebarChromeRow(isSidebarVisible: false, trailingAligned: true) {}
    }
}

#Preview("floating restore") {
    PreviewCanvas(width: 320, background: .canvas) {
        SidebarChromeRow(isSidebarVisible: false) {}
    }
}
