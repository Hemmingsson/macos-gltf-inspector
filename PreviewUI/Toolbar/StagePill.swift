import DesignSystem
import SwiftUI

/// Leading **Stage** cluster — how the scene is dressed.
///
/// Swatches share one island (`DSSwatchPicker`). Floor is its own circle: same Stage job,
/// separate control, so the cluster is never one fused stadium.
public struct StagePill<Viewport: ViewportController>: View {
    public var viewport: Viewport

    public var body: some View {
        DSGlassCluster {
            DSSwatchPicker("Backdrop", selection: backdrop, swatches: swatches)
            DSGlassToggleButton("Floor", systemImage: "circle.grid.cross", isOn: floor)
        }
    }

    private var backdrop: Binding<BackdropStyle> {
        Binding(
            get: { viewport.backdrop },
            set: { viewport.setBackdrop($0) }
        )
    }

    private var floor: Binding<Bool> {
        Binding(
            get: { viewport.showsFloor },
            set: { viewport.setFloor($0) }
        )
    }

    private var swatches: [DSSwatchPicker<BackdropStyle>.Swatch] {
        [
            .init(id: .window, title: BackdropStyle.window.title, fill: .checkerboard),
            .init(id: .white, title: BackdropStyle.white.title, fill: .color(DS.Color.Backdrop.white)),
            .init(id: .dark, title: BackdropStyle.dark.title, fill: .color(DS.Color.Backdrop.dark)),
        ]
    }
}

// MARK: - Previews

private struct StagePillPreviewHost: View {
    @State private var viewport: MockViewportController

    init(viewport: MockViewportController) {
        _viewport = State(initialValue: viewport)
    }

    var body: some View {
        PreviewCanvas(width: 220, height: 64, background: .canvas) {
            StagePill(viewport: viewport)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, DS.Spacing.canvasInset)
        }
    }
}

#Preview("default", traits: .fixedLayout(width: 220, height: 64)) {
    StagePillPreviewHost(viewport: MockViewportController())
}

#Preview("white backdrop", traits: .fixedLayout(width: 220, height: 64)) {
    StagePillPreviewHost(viewport: MockViewportController(backdrop: .white))
}

#Preview("floor off", traits: .fixedLayout(width: 220, height: 64)) {
    StagePillPreviewHost(viewport: MockViewportController(showsFloor: false))
}
