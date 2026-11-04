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
    @ViewBuilder var content: Content

    var body: some View {
        GlassEffectContainer(spacing: DS.Metrics.clusterSpacing) {
            HStack(spacing: DS.Metrics.clusterSpacing) {
                content
            }
        }
        .focusSection()
    }
}
