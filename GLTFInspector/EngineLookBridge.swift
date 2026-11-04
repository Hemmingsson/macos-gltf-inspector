import Foundation
import GLTFCore
import PreviewUI
import Renderer

/// The window's viewport and sidebar as the web canvas's look: the `RenderLook` (through the core
/// mapping) plus the view state the page draws. The page mapping itself lives in `RendererWebKit`.
extension ViewOptions {
    /// `sidebar` is nil until the panels' document has loaded: the file's default scene, nothing
    /// selected.
    @MainActor
    init(_ viewport: some ViewportController, sidebar: HostSidebarModel?) {
        self.init(
            viewport,
            sceneIndex: sidebar?.activeSceneIndex ?? 0,
            fileCameraNodeIndex: sidebar?.selectedCameraNodeIndex,
            selectedNodeIndex: sidebar?.selectedNodeIndex
        )
    }

    @MainActor
    init(
        _ viewport: some ViewportController,
        sceneIndex: Int,
        fileCameraNodeIndex: Int? = nil,
        selectedNodeIndex: Int? = nil
    ) {
        self.init(
            look: RenderLook(viewport.lighting, backdrop: viewport.backdrop),
            viewMode: RenderViewMode(viewport.viewMode),
            autoRotates: viewport.autoRotates,
            isOrthographic: viewport.projection == .orthographic,
            fieldOfView: Double(viewport.fieldOfViewDegrees),
            fileCameraNodeIndex: fileCameraNodeIndex,
            materialVariantIndex: viewport.selectedMaterialVariantIndex,
            sceneIndex: sceneIndex,
            showsFloor: viewport.showsFloor,
            isCentered: viewport.isCentered,
            selectedNodeIndex: selectedNodeIndex
        )
    }
}
