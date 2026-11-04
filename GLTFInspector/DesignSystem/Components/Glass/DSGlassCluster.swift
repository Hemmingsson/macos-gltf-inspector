import SwiftUI

/// One floating group of glass controls on the canvas (Stage, Look, Camera).
///
/// Exactly one `GlassEffectContainer` per cluster, so every island inside samples the backdrop
/// together and renders as one family, while `DS.Metrics.clusterSpacing` (= the island gap) keeps
/// them visually separate at rest (HIG › Materials › "Liquid Glass"; SwiftUI
/// `GlassEffectContainer(spacing:)`). `.focusSection()` makes the cluster one stop for
/// keyboard focus movement between regions.
///
/// Content is a row of islands: `DSGlassIsland`, `DSSwatchPicker`, or standalone glass controls
/// (`DSGlassToggleButton`, `DSGlassMenuButton`, `DSGlassPopoverButton`),
/// each drawing its own single glass layer.
struct DSGlassCluster<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content

    /// - Parameters:
    ///   - spacing: Gap between islands. Defaults to `DS.Metrics.clusterSpacing`.
    ///   - content: The islands, leading to trailing.
    init(
        spacing: CGFloat = DS.Metrics.clusterSpacing,
        @ViewBuilder content: () -> Content
    ) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        GlassEffectContainer(spacing: DS.Metrics.clusterSpacing) {
            HStack(spacing: spacing) {
                content
            }
        }
        .focusSection()
    }
}
