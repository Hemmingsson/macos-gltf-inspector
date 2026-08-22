import SwiftUI

/// Leading **Stage** cluster — how the scene is dressed.
///
/// Sketch-style: only *really* bundled controls share an island. Backdrop swatches are one
/// radio group → one stadium. Floor is its own circle (same Stage job, separate control).
struct StagePill<Viewport: ViewportController>: View {
    var viewport: Viewport

    var body: some View {
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

/// One backdrop choice: a colour disc that takes an accent ring when it is the current one.
struct BackdropSwatch: View {
    var style: BackdropStyle
    var isActive: Bool
    var select: () -> Void

    @Environment(\.previewBorder) private var border

    var body: some View {
        Button(action: select) {
            fill
                .frame(width: PillMetrics.swatchSize, height: PillMetrics.swatchSize)
                .clipShape(.circle)
                .overlay { Circle().strokeBorder(border, lineWidth: 1) }
                .overlay { activeRing }
                .contentShape(.circle)
        }
        .buttonStyle(BackdropSwatchButtonStyle())
        .help(style.title)
        .accessibilityLabel(style.title)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    @ViewBuilder
    private var activeRing: some View {
        if isActive {
            ZStack {
                Circle()
                    .strokeBorder(Theme.card, lineWidth: 2)
                    .frame(width: 24, height: 24)
                Circle()
                    .strokeBorder(Theme.accent, lineWidth: 1.5)
                    .frame(width: 27, height: 27)
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var fill: some View {
        switch style {
        case .window: BackdropCheckerboard()
        case .white: Theme.backdropWhite
        case .dark: Theme.backdropDark
        }
    }
}

private struct BackdropSwatchButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                PreviewFocusStroke(shape: .circle)
                    .frame(width: PillMetrics.swatchSize + 6, height: PillMetrics.swatchSize + 6)
            }
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// The "None" swatch: checkerboard for *no* backdrop.
struct BackdropCheckerboard: View {
    var cell: CGFloat = 5

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.backdropWhite))
            let columns = Int((size.width / cell).rounded(.up))
            let rows = Int((size.height / cell).rounded(.up))
            for row in 0..<rows {
                for column in 0..<columns where (row + column).isMultiple(of: 2) {
                    let square = CGRect(
                        x: CGFloat(column) * cell,
                        y: CGFloat(row) * cell,
                        width: cell,
                        height: cell
                    )
                    context.fill(Path(square), with: .color(Theme.backdropChecker))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
