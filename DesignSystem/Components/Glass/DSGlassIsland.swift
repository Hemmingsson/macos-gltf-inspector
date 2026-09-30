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
public struct DSGlassIsland<Content: View>: View {
    private let horizontalPadding: CGFloat
    private let spacing: CGFloat
    private let content: Content

    /// - Parameters:
    ///   - horizontalPadding: Inset of the first / last control from the capsule's ends.
    ///     Defaults to `DS.Spacing.s`.
    ///   - spacing: Gap between controls. Defaults to `0`, since glass controls already carry
    ///     their own hit-target padding.
    ///   - content: The controls.
    public init(
        horizontalPadding: CGFloat = DS.Spacing.s,
        spacing: CGFloat = 0,
        @ViewBuilder content: () -> Content
    ) {
        self.horizontalPadding = horizontalPadding
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        HStack(spacing: spacing) {
            content
        }
        .buttonStyle(.borderless)
        .dsGlassPlacement(.inIsland)
        .padding(.horizontal, horizontalPadding)
        .frame(height: DS.Metrics.glassControl)
        .glassEffect(DS.Glass.control, in: .capsule)
    }
}

/// The hairline between two groups of controls inside one `DSGlassIsland` or `DSHUDCapsule`:
/// `DS.Metrics.hairline` × `DS.Metrics.islandDividerHeight` in `DS.Color.separator` (which
/// Increase Contrast strengthens). Decorative, so hidden from accessibility.
public struct DSGlassIslandDivider: View {
    public init() {}

    public var body: some View {
        DS.Color.separator
            .frame(width: DS.Metrics.hairline, height: DS.Metrics.islandDividerHeight)
            .padding(.horizontal, DS.Spacing.xs)
            .accessibilityHidden(true)
    }
}

// MARK: - Previews

private struct DSGlassIslandPreview: View {
    @State private var floor = true
    @State private var grid = false

    var body: some View {
        HStack(spacing: DS.Metrics.clusterSpacing) {
            DSGlassIsland {
                DSGlassToggleButton("Floor", systemImage: "circle.grid.cross", isOn: $floor)
                DSGlassToggleButton("Grid", systemImage: "grid", isOn: $grid)
                DSGlassIslandDivider()
                DSGlassIconButton("Frame Model", systemImage: "viewfinder") {}
            }

            DSGlassIsland {
                Button("Plain button") {}
                    .font(DS.Font.body)
                    .padding(.horizontal, DS.Spacing.s)
            }
        }
    }
}

#Preview("island", traits: .sizeThatFitsLayout) {
    DSGlassPreviewBackdrops {
        DSGlassIslandPreview()
    }
    .frame(width: 360)
}
