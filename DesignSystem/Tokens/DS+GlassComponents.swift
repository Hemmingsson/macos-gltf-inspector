import SwiftUI

// Tokens the glass components (`DesignSystem/Components/Glass/`) need beyond the core set.
// Kept in their own file so the core token files stay stable while components land.

public extension DS.Glass {
    /// Strength of the accent tint on an "on" / engaged glass control. Low on purpose: the glass
    /// should read as *subtly* accent-washed with the glyph carrying the full `.tint`, never a
    /// solid prominent disc (HIG › Materials › "Liquid Glass": use tint sparingly, for state).
    static let engagedTintOpacity: Double = 0.18

    /// An interactive control in its on / engaged state: `controlOn` tinted with the user's accent
    /// at `engagedTintOpacity`.
    static var controlEngaged: SwiftUI.Glass {
        controlOn(tint: DS.Color.accent.opacity(engagedTintOpacity))
    }
}

public extension DS.Metrics {
    /// Height of the hairline that separates groups inside one glass island.
    static let islandDividerHeight: CGFloat = 16
    /// Width of that hairline.
    static let hairline: CGFloat = 1
    /// Stroke of the accent ring around the selected backdrop swatch.
    static let swatchRingWidth: CGFloat = 1.5
    /// Clear gap between a selected swatch and its ring.
    static let swatchRingGap: CGFloat = 2
    /// Side of one checkerboard square (the "no backdrop" pattern).
    static let checkerboardCell: CGFloat = 4
}
