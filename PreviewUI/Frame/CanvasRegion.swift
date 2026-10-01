import DesignSystem
import SwiftUI

/// Centre column — the viewport's box and the chrome that floats over it.
///
/// The injected canvas is full-bleed (`.ignoresSafeArea()`, no clipping) so it renders under the
/// floating glass sidebar/inspector and the toolbar band; the pills and bottom overlays stay
/// inside the leading/trailing safe area so they never sit under a pane.
///
/// **Why overlays and not a window toolbar.** The wireframe floats the controls over the 3D
/// content, split into independent clusters. A single `.toolbar` would collapse them into one
/// bar, tie their position to window chrome that this window hides, and put them *above* the
/// canvas instead of on it. Overlays keep each cluster free to size itself and to sit exactly
/// at its own edge.
public struct CanvasRegion<
    Content: View,
    Model: SceneModel,
    Capabilities: Availability,
    Viewport: ViewportController,
    Playback: ClipPlaybackController
>: View {
    /// File snapshot — dimensions and animation clips for the bottom overlays.
    var model: Model
    /// Read-only capability snapshot — the Look pill and playback bar offer only what the file has.
    var availability: Capabilities
    /// The window's live view state. Injected, not owned: the host owns it and the View menu
    /// drives the same instance.
    var viewport: Viewport
    var playback: Playback
    /// Empty / loading / failed hide the model chrome; ready shows pills + overlays.
    var documentState: ShellDocumentState = .ready
    /// When false, Stage clears traffic lights + the floating sidebar restore control.
    var isSidebarVisible: Bool = true
    /// When false, Camera clears the floating inspector Open in action.
    var isInspectorVisible: Bool = true
    /// Restores the sidebar from the canvas overlay when the column is collapsed.
    var onToggleSidebar: () -> Void = {}
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Top safe-area inset (the window toolbar band). Written only from `onGeometryChange`'s
    /// action — never during a view update.
    @State private var topInset: CGFloat = 0

    public var body: some View {
        ZStack {
            Group {
                switch documentState {
                case .ready:
                    content()
                case .empty, .loading, .failed:
                    CanvasStatusView(state: documentState)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DS.Color.Canvas.ground)
            .ignoresSafeArea()

            if documentState.isReady {
                controls
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.safeAreaInsets.top
        } action: { inset in
            topInset = inset
        }
    }

    /// Distance from the top of the (top-safe-area-ignoring) overlay to a 30 pt control whose
    /// center sits on the toolbar band's centerline (the traffic-light line).
    private var bandTopPadding: CGFloat {
        max((topInset - DS.Metrics.glassControl) / 2, DS.Metrics.canvasClusterInset)
    }

    /// Floating chrome. Respects the leading/trailing/bottom safe area (never under a pane);
    /// the top pills ride in the toolbar band.
    private var controls: some View {
        Color.clear
            .allowsHitTesting(false)
            .overlay(alignment: .topLeading) {
                HStack(spacing: DS.Metrics.toolbarClearance) {
                    if !isSidebarVisible {
                        DSGlassIconButton(
                            "Show Sidebar",
                            systemImage: "sidebar.leading",
                            action: onToggleSidebar
                        )
                    }
                    StagePill(viewport: viewport)
                }
                .padding(.leading, stageLeadingInset)
                .padding(.top, bandTopPadding)
            }
            .overlay(alignment: .top) {
                LookPill(availability: availability, viewport: viewport)
                    .padding(.top, bandTopPadding)
            }
            .overlay(alignment: .topTrailing) {
                CameraPill(viewport: viewport)
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
            .overlay(alignment: .bottom) {
                if availability.hasAnimations {
                    PlaybackBar(playback: playback)
                        .padding(.bottom, OverlayMetrics.inset)
                        .transition(reduceMotion ? .identity : .opacity)
                }
            }
            .animation(DS.Motion.chrome(reduceMotion: reduceMotion), value: availability.hasAnimations)
            .animation(DS.Motion.chrome(reduceMotion: reduceMotion), value: viewport.isCentered)
            .animation(DS.Motion.chrome(reduceMotion: reduceMotion), value: model.dimensions.authoredOrigin)
            .animation(DS.Motion.chrome(reduceMotion: reduceMotion), value: isSidebarVisible)
            .animation(DS.Motion.chrome(reduceMotion: reduceMotion), value: isInspectorVisible)
    }

    private var stageLeadingInset: CGFloat {
        isSidebarVisible ? DS.Metrics.canvasClusterInset : DS.Metrics.trafficLightLeadingClearance
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
        case animations
        case collapsedChrome
        case empty
        case loading
        case failed
    }

    var mode: Mode
    @State private var viewport: MockViewportController
    @State private var playback: MockPlaybackController

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .ready, .empty, .loading, .failed:
            _viewport = State(initialValue: MockViewportController())
            _playback = State(initialValue: MockPlaybackController())
        case .animations:
            _viewport = State(initialValue: MockViewportController())
            _playback = State(initialValue: MockPlaybackController(isPlaying: true, time: 0.75))
        case .collapsedChrome:
            _viewport = State(
                initialValue: MockViewportController(
                    isCentered: false,
                    activeSceneID: NodeID(kind: .scene, index: 0)
                )
            )
            _playback = State(initialValue: MockPlaybackController())
        }
    }

    private var documentState: ShellDocumentState {
        switch mode {
        case .ready, .animations, .collapsedChrome: .ready
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

    private var availability: MockAvailability {
        mode == .animations
            ? MockAvailability(hasAnimations: true)
            : MockAvailability()
    }

    private var size: (width: CGFloat, height: CGFloat) {
        switch mode {
        case .ready, .animations, .collapsedChrome: (640, 480)
        case .empty, .loading, .failed: (480, 320)
        }
    }

    var body: some View {
        PreviewCanvas(width: size.width, height: size.height, background: .canvas) {
            CanvasRegion(
                model: model,
                availability: availability,
                viewport: viewport,
                playback: playback,
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

#Preview("animations", traits: .fixedLayout(width: 640, height: 480)) {
    CanvasRegionPreviewHost(mode: .animations)
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
