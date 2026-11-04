import GLTFCore
import Observation

/// Selection, scene, file camera and material variant over the JSON-backed document. The web
/// canvas `Look` reads the scene, selected node and variant from here.
@Observable
@MainActor
final class HostSidebarModel {
    var activeSceneIndex: Int {
        didSet {
            guard activeSceneIndex != oldValue else { return }
            selectedNodeIndex = nil
            selectedCameraNodeIndex = nil
        }
    }
    /// The outliner node carrying the active file camera (the page frames from that node).
    var selectedCameraNodeIndex: Int?
    var selectedNodeIndex: Int?
    /// Nil keeps authored primitive materials; index applies `KHR_materials_variants`.
    var selectedMaterialVariantIndex: Int?
    var materialVariantNames: [String] = []
    let document: GLTFSessionDocument

    init(document: GLTFSessionDocument) {
        self.document = document
        self.activeSceneIndex = document.defaultSceneIndex
    }
}
