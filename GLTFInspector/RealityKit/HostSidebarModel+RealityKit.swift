import RendererRealityKit

/// The RealityKit canvas reads selection, file camera and hide/solo through `PreviewOverlay`.
extension HostSidebarModel: PreviewOverlay {
    var nodeVisibility: PreviewNodeVisibility {
        PreviewNodeVisibility(hidden: hide, soloVisible: soloVisibleIndices)
    }
}
