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
    /// The model's bounds, for the dimensions readout. Nil before the
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
                        .focusSection()
                        .overlay {
                            if view.canvas.showsAnimationTimeline {
                                SpaceKeyView { view.canvas.togglePlayback() }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .allowsHitTesting(false)
                            }
                        }
                        .onKeyPress(.space) {
                            guard view.canvas.showsAnimationTimeline else { return .ignored }
                            view.canvas.togglePlayback()
                            return .handled
                        }
                        // The panes are the leading/trailing safe area: the renderer centres
                        // the model between them. The top band is title bar: drags there move
                        // the window. Written after layout, never during an update.
                        .overlay(alignment: .topLeading) { HoverTooltip(view: view) }
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
            // Bottom overlays.
            .overlay(alignment: .bottomLeading) {
                NavigationGizmo(
                    viewRotation: view.canvas.viewRotation,
                    activePreset: view.activeCameraPreset,
                    onSelect: { view.show($0) },
                    onOrbit: { dx, dy in view.orbit(dx: dx, dy: dy) }
                )
                .allowsHitTesting(view.canvas.phase == .ready)
                .padding(OverlayMetrics.inset)
            }
            .overlay(alignment: .bottomTrailing) {
                DimensionsReadout(size: readout.size, name: readout.name)
                    .padding(.trailing, OverlayMetrics.inset)
                    .padding(.bottom, view.canvas.showsAnimationTimeline
                        ? OverlayMetrics.inset + OverlayMetrics.timelineHeight + DS.Spacing.m
                        : OverlayMetrics.inset)
            }
            .overlay(alignment: .bottom) {
                if view.canvas.showsAnimationTimeline {
                    AnimationTimelineHUD(canvas: view.canvas)
                        .padding(.bottom, OverlayMetrics.inset)
                        .padding(.horizontal, bottomOverlayClearance)
                }
            }
            .animation(DS.Motion.chrome(reduceMotion: reduceMotion), value: view.isCentered)
            .animation(DS.Motion.chrome(reduceMotion: reduceMotion), value: view.canvas.showsAnimationTimeline)
            .animation(DS.Motion.chrome(reduceMotion: reduceMotion), value: isSidebarVisible)
            .animation(DS.Motion.chrome(reduceMotion: reduceMotion), value: isInspectorVisible)
    }

    /// The selected scene node's drawn box when it has one, otherwise the whole model.
    private var readout: (size: SIMD3<Float>, name: String?) {
        SelectionDimensions.readout(view: view, fileBounds: bounds)
    }

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

    /// Keep the timeline between the navigation gizmo and the dimensions readout.
    private var bottomOverlayClearance: CGFloat {
        OverlayMetrics.inset + OverlayMetrics.navigationGizmoSize + DS.Spacing.xl
    }
}

/// The name of the node under the resting pointer, just below and right of it. Its own view, so
/// only it re-renders as the pointer moves.
private struct HoverTooltip: View {
    var view: ViewState

    var body: some View {
        if let node = view.canvas.hoveredNode, let location = view.canvas.hoverLocation,
           let id = view.document.id(ofNode: node) {
            DSHUDCapsule(height: OverlayMetrics.tooltipHeight, horizontalPadding: DS.Spacing.m) {
                Text(view.document.displayName(of: id))
                    .font(.callout)
                    .lineLimit(1)
            }
            .fixedSize()
            .offset(x: location.x + OverlayMetrics.tooltipOffset, y: location.y + OverlayMetrics.tooltipOffset)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .ignoresSafeArea()
        }
    }
}
