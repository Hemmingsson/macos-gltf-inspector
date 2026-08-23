import SwiftUI

/// Leading **Stage** cluster — how the scene is dressed.
///
/// Sketch-style: only *really* bundled controls share an island. Backdrop swatches are one
/// radio group → one stadium. Floor is its own circle (same Stage job, separate control).
public struct StagePill<Viewport: ViewportController>: View {
    public var viewport: Viewport

    public var body: some View {
        HStack(spacing: PillMetrics.islandSpacing) {
            BackdropIsland(viewport: viewport)
            FloorIsland(viewport: viewport)
        }
    }
}

/// Colour backdrop radio — one island, three swatches.
private struct BackdropIsland<Viewport: ViewportController>: View {
    var viewport: Viewport

    var body: some View {
        Pill(horizontalPadding: 6) {
            HStack(spacing: 7) {
                ForEach(BackdropStyle.allCases) { style in
                    BackdropSwatch(style: style, isActive: viewport.backdrop == style) {
                        viewport.setBackdrop(style)
                    }
                }
            }
            .padding(.horizontal, 2)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Backdrop")
        }
    }
}

/// Polar floor — own circle island (not glued to the swatches).
private struct FloorIsland<Viewport: ViewportController>: View {
    var viewport: Viewport

    var body: some View {
        Pill(circle: true) {
            PillButton(
                symbol: "circle.grid.cross",
                title: viewport.showsFloor ? "Hide polar floor" : "Show polar floor",
                isOn: viewport.showsFloor
            ) {
                viewport.setFloor(!viewport.showsFloor)
            }
        }
    }
}
