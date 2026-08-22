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
struct CanvasRegion<
    Content: View,
    Model: SceneModel,
    Capabilities: Availability,
    Viewport: ViewportController
>: View {
    /// File snapshot — dimensions and animation clips for the bottom overlays.
    var model: Model
    /// Read-only capability snapshot — the Look pill and playback bar offer only what the file has.
    var availability: Capabilities
    /// The window's live view state. Injected, not owned: `ShellRootView` owns it and the View
    /// menu will drive the same instance in Slice 7.
    var viewport: Viewport
    /// Empty / loading / failed hide the model chrome; ready shows pills + overlays.
    var documentState: ShellDocumentState = .ready
    /// When false, Stage clears traffic lights + the floating sidebar restore control.
    var isSidebarVisible: Bool = true
    /// When false, Camera clears the floating inspector ActionRow.
    var isInspectorVisible: Bool = true
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
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
            // World-origin cue: Center off (DESIGN.md / Inspect), or an uncentered file
            // (Debug → Uncentered / `authoredOrigin != .zero`) so Slice 6 is one-toggle-one-effect.
            .overlay {
                if !viewport.isCentered || model.dimensions.authoredOrigin != .zero {
                    OriginGizmo(authoredOrigin: model.dimensions.authoredOrigin)
                        .transition(reduceMotion ? .identity : .opacity)
                }
            }
            // Bottom overlays (Slice 5).
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
                    PlaybackBar(clips: model.animations)
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
