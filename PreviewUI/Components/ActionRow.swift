import DesignSystem
import SwiftUI

/// Trailing Open-in control on the traffic-light line — over the canvas while the inspector is
/// closed, over the inspector while it is open, so it never moves vertically and lines up with the
/// toolbar clusters. Callers let it ignore the top safe area.
///
/// `openInMenu` is **menu items** (Finder, Blender, …), not a styled `Menu`. This row wraps them
/// in `DSGlassMenuButton`.
struct ActionRow: View {
    let openInMenu: AnyView

    var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            Spacer(minLength: 0)
            DSGlassMenuButton("Open in", systemImage: "square.and.arrow.up") {
                openInMenu
            }
            .dsGlassPlacement(.standalone)
        }
        .padding(.leading, DS.Spacing.l)
        .padding(.trailing, DS.Spacing.l)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Inspector actions")
        .dsChromeBandAligned()
    }
}

// MARK: - Previews

#Preview("with menu") {
    PreviewCanvas(width: DS.Metrics.inspectorWidth) {
        ActionRow(openInMenu: AnyView(PreviewOpenInItems()))
    }
}
