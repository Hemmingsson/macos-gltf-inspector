import SwiftUI

/// Centre cluster — **Look**: how the surface is shaded and lit.
///
/// View mode + lighting stay one island: both answer “what light does to the material”
/// (Sketch-style — only split when controls are not a real bundle).
public struct LookPill<Capabilities: Availability, Viewport: ViewportController>: View {
    /// Read-only capability snapshot: the view-mode menu offers only channels the file has.
    public var availability: Capabilities
    public var viewport: Viewport

    public var body: some View {
        // `padding: 0 6px` — the chip inside carries its own leading padding.
        Pill(horizontalPadding: 6) {
            ViewModeMenu(availability: availability, viewport: viewport)
            PillDivider()
            LightingPopover(availability: availability, viewport: viewport)
        }
    }
}
