import SwiftUI

/// Centre column — the viewport's box and the chrome that floats over it.
///
/// Owns the clipping and the ground colour so whatever is injected (a placeholder now, a
/// `RealityView` later) cannot bleed past the hairlines, and owns the toolbar pills *and*
/// bottom overlays so they are positioned in the *canvas'* coordinate space rather than the
/// window's.
///
/// **Why overlays and not a window toolbar.** The wireframe floats the controls over the 3D
/// content, split into independent clusters. A single `.toolbar` would collapse them into one
/// bar, tie their position to window chrome that this window deliberately hides, and put them
/// *above* the canvas instead of on it. Overlays keep each cluster free to size itself and to
/// sit exactly at its own edge.
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
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var body: some View {
        Group {
            switch documentState {
            case .ready:
                readyCanvas
            case .empty, .loading, .failed:
                CanvasStatusView(state: documentState)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas)
        .clipped()
    }

    private var readyCanvas: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Top toolbar — Sketch-style islands on the traffic-light centerline.
            .overlay(alignment: .topLeading) {
                StagePill(viewport: viewport)
                    .padding(.leading, stageLeadingInset)
                    .chromeBandAligned()
            }
            .overlay(alignment: .top) {
                LookPill(availability: availability, viewport: viewport)
                    .chromeBandAligned()
            }
            .overlay(alignment: .topTrailing) {
                CameraPill(viewport: viewport)
                    .padding(.trailing, cameraTrailingInset)
                    .chromeBandAligned()
            }
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
            .animation(Animation.previewChrome(reduceMotion), value: availability.hasAnimations)
            .animation(Animation.previewChrome(reduceMotion), value: viewport.isCentered)
            .animation(Animation.previewChrome(reduceMotion), value: model.dimensions.authoredOrigin)
            .animation(Animation.previewChrome(reduceMotion), value: isSidebarVisible)
            .animation(Animation.previewChrome(reduceMotion), value: isInspectorVisible)
    }

    private var stageLeadingInset: CGFloat {
        isSidebarVisible ? PillMetrics.inset : ChromeMetrics.collapsedLeadingInset
    }

    private var cameraTrailingInset: CGFloat {
        isInspectorVisible ? PillMetrics.inset : ChromeMetrics.collapsedTrailingInset
    }
}

// MARK: - Previews

/// Stand-in for the host-injected `RealityView` — flat gray viewport only.
private struct CanvasPlaceholder: View {
    var body: some View {
        Theme.canvasGradient
    }
}

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
                content: { CanvasPlaceholder() }
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
