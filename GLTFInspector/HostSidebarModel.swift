import RealityKit
import SwiftUI

@Observable
@MainActor
final class HostSidebarModel: PreviewOverlay {
    var hide = Set<Int>()
    /// When set, only this node, its ancestors, and its descendants stay visible.
    var soloRoot: Int?
    var activeSceneIndex: Int {
        didSet {
            guard activeSceneIndex != oldValue else { return }
            selectedNodeIndex = nil
            soloRoot = nil
            overlayRevision += 1
        }
    }
    var selectedCameraIndex: Int?
    var selectedNodeIndex: Int?
    /// Nil keeps authored primitive materials; index applies `KHR_materials_variants`.
    var selectedMaterialVariantIndex: Int?
    var materialVariantNames: [String] = []
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

    /// Isolate `id`'s subtree (toggle off if already isolating that node).
    func isolate(_ id: Int) {
        soloRoot = soloRoot == id ? nil : id
        overlayRevision += 1
    }

    func showAll() {
        hide.removeAll()
        soloRoot = nil
        overlayRevision += 1
    }

    /// True when solo is active and `id` is outside the isolated path/subtree.
    func soloHides(_ id: Int) -> Bool {
        guard let soloRoot else { return false }
        return !isolatedVisibleIndices(of: soloRoot).contains(id)
    }

    func applyIfNeeded(to root: Entity) {
        guard overlayRevision != appliedRevision else { return }
        appliedRevision = overlayRevision
        applyVisibility(to: root)
        PreviewSelectionVisuals.apply(selectedNodeIndex: selectedNodeIndex, to: root)
    }

    /// Solo root + ancestors + descendants (the nodes that stay enabled).
    private func isolatedVisibleIndices(of root: Int) -> Set<Int> {
        var visible: Set<Int> = [root]
        visible.formUnion(ancestorIndices(of: root))
        visible.formUnion(descendantIndices(of: root))
        return visible
    }

    private func ancestorIndices(of id: Int) -> Set<Int> {
        let parentOf = Dictionary(
            uniqueKeysWithValues: document.nodes.flatMap { node in
                node.children.map { ($0, node.index) }
            }
        )
        var found = Set<Int>()
        var current = id
        while let parent = parentOf[current] {
            found.insert(parent)
            current = parent
        }
        return found
    }

    private func descendantIndices(of root: Int) -> Set<Int> {
        let nodesByIndex = Dictionary(uniqueKeysWithValues: document.nodes.map { ($0.index, $0) })
        var found = Set<Int>()
        var stack = [root]
        while let id = stack.popLast() {
            guard let children = nodesByIndex[id]?.children else { continue }
            for child in children {
                found.insert(child)
                stack.append(child)
            }
        }
        return found
    }

    private func applyVisibility(to entity: Entity) {
        let soloVisible = soloRoot.map { isolatedVisibleIndices(of: $0) }
        applyVisibility(to: entity, soloVisible: soloVisible)
    }

    private func applyVisibility(to entity: Entity, soloVisible: Set<Int>?) {
        if let id = entity.components[GLTFNodeIDComponent.self]?.nodeIndex {
            let hiddenBySolo = soloVisible.map { !$0.contains(id) } ?? false
            entity.isEnabled = !hide.contains(id) && !hiddenBySolo
        }
        for child in entity.children {
            applyVisibility(to: child, soloVisible: soloVisible)
        }
    }
}
