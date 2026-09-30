import SwiftUI

/// One floating group of glass controls on the canvas (Stage, Look, Camera).
///
/// Exactly one `GlassEffectContainer` per cluster, so every island inside samples the backdrop
/// together and renders as one family, while `DS.Glass.containerSpacing` (= the island gap) keeps
/// them visually separate at rest (HIG › Materials › "Liquid Glass"; SwiftUI
/// `GlassEffectContainer(spacing:)`). `.focusSection()` makes the cluster one stop for
/// keyboard focus movement between regions.
///
/// Content is a row of islands: `DSGlassIsland`, `DSSwatchPicker`, or standalone glass controls
/// (`DSGlassToggleButton`, `DSGlassIconButton`, `DSGlassMenuButton`, `DSGlassPopoverButton`),
/// each drawing its own single glass layer.
public struct DSGlassCluster<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content

    /// - Parameters:
    ///   - spacing: Gap between islands. Defaults to `DS.Metrics.clusterSpacing`.
    ///   - content: The islands, leading to trailing.
    public init(
        spacing: CGFloat = DS.Metrics.clusterSpacing,
        @ViewBuilder content: () -> Content
    ) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        GlassEffectContainer(spacing: DS.Glass.containerSpacing) {
            HStack(spacing: spacing) {
                content
            }
        }
        .focusSection()
    }
}

// MARK: - Previews

private struct DSGlassClusterPreview: View {
    @State private var floor = true
    @State private var autoRotate = true
    @State private var centered = true
    @State private var orthographic = false
    @State private var backdrop = 0

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.l) {
            DSGlassCluster {
                DSSwatchPicker(
                    "Backdrop",
                    selection: $backdrop,
                    swatches: [
                        .init(id: 0, title: "Checkerboard", fill: .checkerboard),
                        .init(id: 1, title: "White", fill: .color(DS.Color.Backdrop.white)),
                        .init(id: 2, title: "Dark", fill: .color(DS.Color.Backdrop.dark))
                    ]
                )
                DSGlassToggleButton("Floor", systemImage: "circle.grid.cross", isOn: $floor)
            }

            DSGlassCluster {
                DSGlassIsland {
                    DSGlassMenuButton(
                        "View mode",
                        systemImage: "circle.lefthalf.filled",
                        style: .titled("Shaded")
                    ) {
                        Button("Shaded") {}
                        Button("Wireframe") {}
                    }
                    DSGlassIslandDivider()
                    DSGlassPopoverButton("Lighting", systemImage: "sun.max") {
                        Text("Lighting controls").padding(DS.Spacing.xl)
                    }
                }
            }

            DSGlassCluster {
                DSGlassToggleButton(
                    "Auto-rotate",
                    systemImage: "arrow.trianglehead.counterclockwise.rotate.90",
                    isOn: $autoRotate
                )
                DSGlassToggleButton("Center Model", systemImage: "dot.scope", isOn: $centered)
                DSGlassToggleButton("Orthographic", systemImage: "perspective", isOn: $orthographic)
                DSGlassPopoverButton("Field of View", systemImage: "camera.aperture") {
                    Text("Field of view controls").padding(DS.Spacing.xl)
                }
                DSGlassIconButton("Frame Model", systemImage: "viewfinder") {}
                DSGlassMenuButton("Camera presets", systemImage: "cube") {
                    Button("Front") {}
                    Button("Top") {}
                }
            }
        }
    }
}

#Preview("clusters", traits: .sizeThatFitsLayout) {
    DSGlassPreviewBackdrops {
        DSGlassClusterPreview()
    }
    .frame(width: 520)
}
