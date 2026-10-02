import DesignSystem
import SwiftUI

/// Trailing Open-in control. In the inspector header it sits padded at the top right; over the
/// canvas (inspector hidden) it still sits on the chrome baseline so the floating overlay stays
/// reachable.
///
/// `openInMenu` is **menu items** (Finder, Blender, …), not a styled `Menu`. This row wraps them
/// in `DSGlassMenuButton`.
struct ActionRow: View {
    let openInMenu: AnyView
    /// When `true`, align to the window chrome band (floating canvas overlay). The inspector
    /// header passes `false` and pads instead.
    var alignsToChromeBand: Bool = true

    var body: some View {
        let row = HStack(spacing: DS.Spacing.xs) {
            Spacer(minLength: 0)
            DSGlassMenuButton("Open in", systemImage: "square.and.arrow.up") {
                openInMenu
            }
            .dsGlassPlacement(alignsToChromeBand ? .standalone : .inIsland)
        }
        .padding(.leading, DS.Spacing.l)
        .padding(.trailing, DS.Spacing.l)
        .padding(.top, alignsToChromeBand ? 0 : DS.Spacing.s)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Inspector actions")

        if alignsToChromeBand {
            row.dsChromeBandAligned()
        } else {
            row
        }
    }
}

// MARK: - Previews

#Preview("with menu") {
    PreviewCanvas(width: DS.Metrics.inspectorWidth) {
        ActionRow(openInMenu: AnyView(PreviewOpenInItems()), alignsToChromeBand: false)
    }
}
