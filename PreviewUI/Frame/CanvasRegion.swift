import DesignSystem
import SwiftUI

/// Centre column — the viewport's box and the chrome that floats over it.
///
/// The injected canvas is full-bleed (`.ignoresSafeArea()`, no clipping) so it renders under the
/// floating glass sidebar/inspector and the toolbar band; the clusters and bottom overlays stay
/// inside the leading/trailing safe area so they never sit under a pane.
///
/// **Why overlays and not a window toolbar.** The wireframe floats the controls over the 3D
/// content, split into independent clusters. A single `.toolbar` would collapse them into one
/// bar, tie their position to window chrome that this window hides, and put them *above* the
/// canvas instead of on it. Overlays keep each cluster free to size itself and to sit exactly
/// at its own edge.
struct CanvasRegion<
    Content: View,
    Model: SceneModel,
    Viewport: ViewportController
>: View {
    /// File snapshot — dimensions for the bottom overlays.
    var model: Model
    /// The Look cluster offers only the view modes the file has.
    var availability: Availability
    /// The window's live view state. Injected, not owned: the host owns it and the View menu
    /// drives the same instance.
    var viewport: Viewport
    /// Empty / loading / failed hide the model chrome; ready shows clusters + overlays.
    var documentState: ShellDocumentState = .ready
    /// When false, Stage clears the traffic lights and the system sidebar toggle beside them.
    var isSidebarVisible: Bool = true
    /// When false, Camera clears the floating inspector Open in action.
    var isInspectorVisible: Bool = true
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.canvasFileDrop) private var canvasFileDrop
    /// Drop highlight. Written from the drop callback, never during a view update.
    @State private var dropTargeted = false

    var body: some View {
        ZStack {
            Group {
                switch documentState {
                case .ready:
                    content()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(DS.Color.Canvas.ground)
                        .ignoresSafeArea()
                case .empty, .loading, .failed:
                    // Stay inside the safe area so the empty group centers in the visible pane.
                    ShellStatusView(state: documentState, placement: .canvas)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                canvasFileDrop(providers)
            }
            .overlay {
                if dropTargeted {
                    RoundedRectangle(cornerRadius: DS.Radius.pane, style: .continuous)
                        .strokeBorder(DS.Color.textTertiary, lineWidth: DS.Metrics.hairline)
                        .padding(DS.Spacing.l)
                        .allowsHitTesting(false)
                }
            }

            if documentState.isReady {
                controls
            }
        }
    }

    /// Distance from the window top to a glass control whose center sits on the traffic-light
    /// line — the same line as the system sidebar toggle and the inspector's Open-in button.
    private var bandTopPadding: CGFloat {
        DS.Metrics.toolbarCenterY - DS.Metrics.glassControl / 2
    }

    /// Floating chrome. Respects the leading/trailing/bottom safe area (never under a pane);
    /// the top clusters ride in the toolbar band.
    private var controls: some View {
        Color.clear
            .allowsHitTesting(false)
            .overlay(alignment: .topLeading) {
                StageCluster(viewport: viewport)
                    .padding(.leading, stageLeadingInset)
                .padding(.top, bandTopPadding)
            }
            .overlay(alignment: .top) {
                LookCluster(availability: availability, viewport: viewport)
                    .padding(.top, bandTopPadding)
            }
            .overlay(alignment: .topTrailing) {
                CameraCluster(viewport: viewport)
                    .padding(.trailing, cameraTrailingInset)
                    .padding(.top, bandTopPadding)
            }
            .ignoresSafeArea(.container, edges: .top)
            // World-origin cue: shown when Center is off, or when the file is uncentered
            // (`authoredOrigin != .zero`), so the Center toggle has one clear effect.
            .overlay {
                if !viewport.isCentered || model.dimensions.authoredOrigin != .zero {
                    OriginGizmo(authoredOrigin: model.dimensions.authoredOrigin)
                        .transition(reduceMotion ? .identity : .opacity)
                }
            }
            // Bottom overlays.
            .overlay(alignment: .bottomLeading) {
                OrientationGizmo()
                    .padding(OverlayMetrics.inset)
            }
            .overlay(alignment: .bottomTrailing) {
                DimensionsReadout(dimensions: model.dimensions)
                    .padding(OverlayMetrics.inset)
            }
            .animation(DS.Motion.chrome(reduceMotion: reduceMotion), value: viewport.isCentered)
            .animation(DS.Motion.chrome(reduceMotion: reduceMotion), value: model.dimensions.authoredOrigin)
            .animation(DS.Motion.chrome(reduceMotion: reduceMotion), value: isSidebarVisible)
            .animation(DS.Motion.chrome(reduceMotion: reduceMotion), value: isInspectorVisible)
    }

    private var stageLeadingInset: CGFloat {
        // Collapsed: the system sidebar toggle stays in the band after the traffic lights.
        isSidebarVisible
            ? DS.Metrics.canvasClusterInset
            : DS.Metrics.trafficLightLeadingClearance + DS.Metrics.glassControl
                + DS.Metrics.toolbarClearance + DS.Metrics.clusterSpacing
    }

    private var cameraTrailingInset: CGFloat {
        isInspectorVisible
            ? DS.Metrics.canvasClusterInset
            : DS.Metrics.glassControl + DS.Spacing.l + DS.Spacing.l + DS.Metrics.toolbarClearance
    }
}

// MARK: - Previews

private struct CanvasRegionPreviewHost: View {
    enum Mode {
        case ready
        case collapsedChrome
        case empty
        case loading
        case failed
    }

    var mode: Mode
    @State private var viewport: MockViewportController

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .ready, .empty, .loading, .failed:
            _viewport = State(initialValue: MockViewportController())
        case .collapsedChrome:
            _viewport = State(
                initialValue: MockViewportController(
                    isCentered: false,
                    activeSceneID: NodeID(kind: .scene, index: 0)
                )
            )
        }
    }

    private var documentState: ShellDocumentState {
        switch mode {
        case .ready, .collapsedChrome: .ready
        case .empty: .empty
        case .loading: .loading
        case .failed: .failed(ShellStatusCopy.invalidFileDetail)
        }
    }

    private var model: FixtureSceneModel {
        switch mode {
        case .collapsedChrome:
            var offcenter = FixtureSceneModel.cube
            offcenter.dimensions = Dimensions(
                width: 1,
                height: 1,
                depth: 1,
                authoredOrigin: Vector3(x: 0.42, y: -0.18, z: 1.05)
            )
            return offcenter
        default:
            return FixtureSceneModel.cube
        }
    }

    private var size: (width: CGFloat, height: CGFloat) {
        switch mode {
        case .ready, .collapsedChrome: (640, 480)
        case .empty, .loading, .failed: (480, 320)
        }
    }

    var body: some View {
        PreviewCanvas(width: size.width, height: size.height, background: .canvas) {
            CanvasRegion(
                model: model,
                availability: Availability.preview,
                viewport: viewport,
                documentState: documentState,
                isSidebarVisible: mode != .collapsedChrome,
                isInspectorVisible: mode != .collapsedChrome,
                content: { PreviewCanvasPlaceholder() }
            )
        }
    }
}

#Preview("ready", traits: .fixedLayout(width: 640, height: 480)) {
    CanvasRegionPreviewHost(mode: .ready)
}

#Preview("collapsed chrome", traits: .fixedLayout(width: 640, height: 480)) {
    CanvasRegionPreviewHost(mode: .collapsedChrome)
}

#Preview("empty", traits: .fixedLayout(width: 480, height: 320)) {
    CanvasRegionPreviewHost(mode: .empty)
}

#Preview("loading", traits: .fixedLayout(width: 480, height: 320)) {
    CanvasRegionPreviewHost(mode: .loading)
}

#Preview("failed", traits: .fixedLayout(width: 480, height: 320)) {
    CanvasRegionPreviewHost(mode: .failed)
}
