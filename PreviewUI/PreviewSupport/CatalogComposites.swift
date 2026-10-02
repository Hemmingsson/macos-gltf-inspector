import DesignSystem
import SwiftUI

/// Public constructors for the canvas and pane composites, so the `DesignCatalog` app (another
/// module) can render the real PreviewUI views over PreviewSupport mocks.
///
/// The composites are in-module types (the shell builds them here); this keeps that API
/// unchanged while the catalog shows the live PreviewUI chrome. Each function returns exactly
/// what the shell places on screen.
public enum CatalogComposites {
    /// Leading Stage cluster (backdrop swatches + floor).
    public static func stageCluster(viewport: some ViewportController) -> some View {
        StageCluster(viewport: viewport)
    }

    /// Centre Look cluster (view-mode menu │ lighting chip).
    public static func lookCluster(
        availability: some Availability,
        viewport: some ViewportController
    ) -> some View {
        LookCluster(availability: availability, viewport: viewport)
    }

    /// Trailing Camera cluster (auto-rotate, center, projection, FoV, fit, presets).
    public static func cameraCluster(viewport: some ViewportController) -> some View {
        CameraCluster(viewport: viewport)
    }

    /// The lighting chip; click opens the live popover. Standalone so it draws its own glass.
    public static func lightingChip(
        availability: some Availability,
        viewport: some ViewportController
    ) -> some View {
        LightingPopover(availability: availability, viewport: viewport)
    }

    /// The lighting popover body, hosted inline.
    public static func lightingControls(
        availability: some Availability,
        viewport: some ViewportController
    ) -> some View {
        LightingControls(availability: availability, viewport: viewport)
    }

    /// The field-of-view chip; click opens the live popover. Standalone so it draws its own glass.
    public static func fieldOfViewChip(viewport: some ViewportController) -> some View {
        FieldOfViewPopover(viewport: viewport)
    }

    /// The field-of-view popover body, hosted inline.
    public static func fieldOfViewControls(viewport: some ViewportController) -> some View {
        FieldOfViewControls(viewport: viewport)
    }

    /// Bottom-centre playback bar.
    public static func playbackBar(playback: some ClipPlaybackController) -> some View {
        PlaybackBar(playback: playback)
    }

    /// Left sidebar column at its fixed shell width.
    public static func sidebar(
        model: some SceneModel,
        selection: some SelectionModel,
        viewport: some ViewportController,
        documentState: ShellDocumentState = .ready
    ) -> some View {
        LeftSidebar(
            model: model,
            selection: selection,
            viewport: viewport,
            documentState: documentState,
            isSidebarVisible: true,
            onToggleSidebar: {}
        )
        .frame(width: DS.Metrics.sidebarWidth)
    }

    /// Right inspector column at its fixed shell width.
    ///
    /// `openInMenu` is menu *items* (Finder, Blender, …). The inspector wraps them in
    /// `DSGlassMenuButton`. Passing a styled `Menu` nests a submenu.
    public static func inspector(
        selection: some SelectionModel,
        documentState: ShellDocumentState = .ready,
        openInMenu: AnyView,
        morphTargets: [MorphTargetControl] = []
    ) -> some View {
        RightInspector(
            selection: selection,
            documentState: documentState,
            openInMenu: openInMenu,
            morphTargets: morphTargets
        )
        .frame(width: DS.Metrics.inspectorWidth)
    }
}
