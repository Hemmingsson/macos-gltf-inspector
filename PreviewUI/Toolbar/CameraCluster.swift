import DesignSystem
import SwiftUI

/// Trailing **Camera** cluster — where you stand and how you move.
///
/// One `DSGlassCluster`: auto-rotate, center, orthographic, FoV, and the View menu (zoom, fit,
/// camera angles). Each control
/// draws its own glass; nothing is nested glass-on-glass.
struct CameraCluster<Viewport: ViewportController>: View {
    var viewport: Viewport
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        DSGlassCluster {
            DSGlassToggleButton(
                "Auto-rotate",
                systemImage: "arrow.trianglehead.counterclockwise.rotate.90",
                isOn: autoRotate
            )
            .disabled(reduceMotion)

            DSGlassToggleButton("Center Model", systemImage: "dot.scope", isOn: center)

            DSGlassToggleButton("Orthographic", systemImage: "perspective", isOn: orthographic)

            FieldOfViewPopover(viewport: viewport)

            ViewMenu(viewport: viewport)
        }
    }

    /// Reduce Motion parks the toggle off even if the session flag is still set.
    private var autoRotate: Binding<Bool> {
        Binding(
            get: { viewport.autoRotates && !reduceMotion },
            set: { newValue in
                guard !reduceMotion else { return }
                viewport.setAutoRotate(newValue)
            }
        )
    }

    private var center: Binding<Bool> {
        Binding(
            get: { viewport.isCentered },
            set: { viewport.setCenter($0) }
        )
    }

    private var orthographic: Binding<Bool> {
        Binding(
            get: { viewport.projection == .orthographic },
            set: { viewport.setProjection($0 ? .orthographic : .perspective) }
        )
    }
}

// MARK: - Previews

private struct CameraClusterPreviewHost: View {
    @State private var viewport: MockViewportController

    init(viewport: MockViewportController) {
        _viewport = State(initialValue: viewport)
    }

    var body: some View {
        PreviewCanvas(width: 420, height: 64, background: .canvas) {
            CameraCluster(viewport: viewport)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.trailing, DS.Spacing.canvasInset)
        }
    }
}

#Preview("default", traits: .fixedLayout(width: 420, height: 64)) {
    CameraClusterPreviewHost(viewport: MockViewportController())
}

#Preview("orthographic", traits: .fixedLayout(width: 420, height: 64)) {
    CameraClusterPreviewHost(viewport: MockViewportController(projection: .orthographic))
}

#Preview("auto-rotate", traits: .fixedLayout(width: 420, height: 64)) {
    CameraClusterPreviewHost(viewport: MockViewportController(autoRotates: true))
}

#Preview("preset front", traits: .fixedLayout(width: 420, height: 64)) {
    CameraClusterPreviewHost(viewport: MockViewportController(activeCameraPreset: .front))
}
