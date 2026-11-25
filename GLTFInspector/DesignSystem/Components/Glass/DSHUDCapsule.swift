import SwiftUI

/// A non-interactive glass readout on the canvas, such as the dimensions readout.
///
/// One capsule of `DS.Glass.hud` (`Glass.regular`, not interactive — the capsule itself is not a
/// control). Buttons inside are borderless and the DS glass controls draw no glass of their own
/// (`DSGlassPlacement.inIsland`), so nothing inside is glass on glass. Separate groups with
/// `DSGlassIslandDivider()`.
struct DSHUDCapsule<Content: View>: View {
    private let height: CGFloat
    private let horizontalPadding: CGFloat
    private let spacing: CGFloat
    private let content: Content

    /// - Parameters:
    ///   - height: Capsule height. Defaults to `DS.Metrics.glassControl`.
    ///   - horizontalPadding: Inset from the capsule's ends. Defaults to `DS.Spacing.l`.
    ///   - spacing: Gap between items. Defaults to `DS.Spacing.m`.
    ///   - content: The readout.
    init(
        height: CGFloat = DS.Metrics.glassControl,
        horizontalPadding: CGFloat = DS.Spacing.l,
        spacing: CGFloat = DS.Spacing.m,
        @ViewBuilder content: () -> Content
    ) {
        self.height = height
        self.horizontalPadding = horizontalPadding
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        HStack(spacing: spacing) {
            content
        }
        .buttonStyle(.borderless)
        .dsGlassPlacement(.inIsland)
        .padding(.horizontal, horizontalPadding)
        .frame(height: height)
        .glassEffect(DS.Glass.hud, in: .capsule)
    }
}
