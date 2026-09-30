import Foundation
import GLTFCore
import PreviewUI
import RendererWebKit

/// The window's viewport as the web canvas's look: the neutral `RenderLook` (through the core
/// mapping) plus the view state the page draws. The page mapping itself lives in `RendererWebKit`.
extension WebPreviewCanvas.Look {
    @MainActor
    init(_ viewport: some ViewportController, sceneIndex: Int, selectedNodeIndex: Int? = nil) {
        self.init(
            render: RenderLook(viewport.lighting, backdrop: viewport.backdrop),
            viewMode: RenderViewMode(viewport.viewMode),
            autoRotates: viewport.autoRotates,
            isOrthographic: viewport.projection == .orthographic,
            fieldOfView: Double(viewport.fieldOfViewDegrees),
            materialVariantIndex: viewport.selectedMaterialVariantIndex,
            sceneIndex: sceneIndex,
            showsFloor: viewport.showsFloor,
            isCentered: viewport.isCentered,
            selectedNodeIndex: selectedNodeIndex
        )
    }
}
