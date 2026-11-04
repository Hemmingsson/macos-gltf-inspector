import SwiftUI

/// One capsule of glass holding several related controls (the Look island: view mode │ lighting;
/// the backdrop swatches).
///
/// The island draws the **only** glass layer: `.glassEffect(DS.Glass.control, in: .capsule)` at a
/// fixed `DS.Metrics.glassControl` height. Everything inside is borderless and draws no glass of
/// its own — the island sets `DSGlassPlacement.inIsland`, which the DS glass controls read, and
/// `.buttonStyle(.borderless)` for any plain `Button` placed inside. Separate groups with
/// `DSGlassIslandDivider()`.
///
/// Place islands in a `DSGlassCluster` so they share one `GlassEffectContainer`.
struct DSGlassIsland<Content: View>: View {
    /// Gap between controls; glass controls carry their own hit padding, so 0 by default.
    var spacing: CGFloat = 0
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: spacing) {
            content
        }
        .buttonStyle(.borderless)
        .dsGlassPlacement(.inIsland)
        .padding(.horizontal, DS.Spacing.s)
        .frame(height: DS.Metrics.glassControl)
        .glassEffect(DS.Glass.control, in: .capsule)
    }
}

/// The hairline between two groups of controls inside one `DSGlassIsland` or `DSHUDCapsule`:
/// `DS.Metrics.hairline` × `DS.Metrics.islandDividerHeight` in `DS.Color.separator` (which
/// Increase Contrast strengthens). Decorative, so hidden from accessibility.
struct DSGlassIslandDivider: View {
    var body: some View {
        DS.Color.separator
            .frame(width: DS.Metrics.hairline, height: DS.Metrics.islandDividerHeight)
            .padding(.horizontal, DS.Spacing.xs)
            .accessibilityHidden(true)
    }
}
