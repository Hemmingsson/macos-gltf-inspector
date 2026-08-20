import RealityKit
import SwiftUI

@Observable
@MainActor
final class HostSidebarModel: PreviewOverlay {
    var hide = Set<Int>()
    var activeSceneIndex: Int {
        didSet {
            guard activeSceneIndex != oldValue else { return }
            selectedNodeIndex = nil
            overlayRevision += 1
        }
    }
    var selectedCameraIndex: Int?
    var selectedNodeIndex: Int?
    var overlayRevision = 0
    let document: GLTFSessionDocument

    @ObservationIgnored private var appliedRevision = Int.min

    init(document: GLTFSessionDocument) {
        self.document = document
        self.activeSceneIndex = document.defaultSceneIndex
    }

    func layerRootIndices() -> [Int] {
        guard document.scenes.indices.contains(activeSceneIndex) else { return [] }
        return document.scenes[activeSceneIndex].rootNodeIndices
    }

    func selectNode(_ id: Int) {
        selectedNodeIndex = selectedNodeIndex == id ? nil : id
        overlayRevision += 1
    }

    func showAll() {
        hide.removeAll()
        overlayRevision += 1
    }

    func applyIfNeeded(to root: Entity) {
        guard overlayRevision != appliedRevision else { return }
        appliedRevision = overlayRevision
        applyVisibility(to: root)
        PreviewSelectionVisuals.apply(selectedNodeIndex: selectedNodeIndex, to: root)
    }

    private func applyVisibility(to entity: Entity) {
        if let id = entity.components[GLTFNodeIDComponent.self]?.nodeIndex {
            entity.isEnabled = !hide.contains(id)
        }
        for child in entity.children {
            applyVisibility(to: child)
        }
    }
}
