import GLTFCore
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
struct CanvasRegion<Content: View>: View {
    /// The model's bounds, for the dimensions readout and the origin gizmo. Nil before the
    /// file's JSON is read, or when it has no measurable mesh.
    var bounds: ModelBounds?
    var view: ViewState
    /// Empty / loading / failed hide the model chrome; ready shows clusters + overlays.
    var documentState: DocumentState = .ready
    /// When false, Stage clears the traffic lights and the system sidebar toggle beside them.
    var isSidebarVisible: Bool = true
    /// When false, Camera clears the floating inspector Open in action.
    var isInspectorVisible: Bool = true
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openDocument) private var openDocument
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
                        // The panes are the leading/trailing safe area: the renderer centres
                        // the model between them. The top band is title bar: drags there move
                        // the window. Written after layout, never during an update.
                        .onGeometryChange(for: EdgeInsets.self, of: \.safeAreaInsets) { insets in
                            view.canvas.contentInsets = NSEdgeInsets(
                                top: DS.Metrics.toolbarBandHeight, left: insets.leading,
                                bottom: 0, right: insets.trailing
                            )
                        }
                case .empty, .loading, .failed:
                    // Stay inside the safe area so the empty group centers in the visible pane.
                    DocumentStatusView(state: documentState, placement: .canvas)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                DocumentOpening.handleDrop(providers, openDocument: openDocument)
            }
            .overlay {
                if dropTargeted {
                    RoundedRectangle(cornerRadius: DS.Radius.pane, style: .continuous)
                        .strokeBorder(.tertiary, lineWidth: DS.Metrics.hairline)
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
                StageCluster(view: view)
                    .padding(.leading, stageLeadingInset)
                .padding(.top, bandTopPadding)
            }
            .overlay(alignment: .top) {
                LookCluster(view: view)
                    .padding(.top, bandTopPadding)
            }
            .overlay(alignment: .topTrailing) {
                CameraCluster(view: view)
                    .padding(.trailing, cameraTrailingInset)
                    .padding(.top, bandTopPadding)
            }
            .ignoresSafeArea(.container, edges: .top)
            // World-origin cue: shown when Center is off, or when the file is uncentered
            // (`authoredOrigin != .zero`), so the Center toggle has one clear effect.
            .overlay {
                if !view.isCentered || authoredOrigin != .zero {
                    OriginGizmo(authoredOrigin: authoredOrigin)
                        .transition(reduceMotion ? .identity : .opacity)
                }
            }
            // Bottom overlays.
            .overlay(alignment: .bottomLeading) {
                OrientationGizmo()
                    .padding(OverlayMetrics.inset)
            }
            .overlay(alignment: .bottomTrailing) {
                DimensionsReadout(size: bounds?.size ?? .zero)
                    .padding(OverlayMetrics.inset)
            }
            .animation(DS.Motion.chrome(reduceMotion: reduceMotion), value: view.isCentered)
            .animation(DS.Motion.chrome(reduceMotion: reduceMotion), value: authoredOrigin)
            .animation(DS.Motion.chrome(reduceMotion: reduceMotion), value: isSidebarVisible)
            .animation(DS.Motion.chrome(reduceMotion: reduceMotion), value: isInspectorVisible)
    }

    private var authoredOrigin: SIMD3<Float> { bounds?.authoredOrigin ?? .zero }

    private var stageLeadingInset: CGFloat {
        // Collapsed: Stage follows the traffic lights in the band (no sidebar toggle; ⌘B).
        isSidebarVisible
            ? DS.Metrics.canvasClusterInset
            : DS.Metrics.trafficLightLeadingClearance + DS.Metrics.canvasClusterInset
    }

    private var cameraTrailingInset: CGFloat {
        isInspectorVisible
            ? DS.Metrics.canvasClusterInset
            : DS.Metrics.glassControl + DS.Spacing.l + DS.Spacing.l + DS.Metrics.toolbarClearance
    }
}
