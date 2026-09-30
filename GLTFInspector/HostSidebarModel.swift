import GLTFCore
import Observation

@Observable
@MainActor
/// Selection, scenes, variants and hide/solo over the JSON-backed document. Renderer-neutral;
/// the RealityKit canvas reads it as a `PreviewOverlay` (`RealityKit/HostSidebarModel+RealityKit.swift`).
final class HostSidebarModel {
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

    @ObservationIgnored var appliedOverlayRevision = Int.min

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

    /// Nodes that stay enabled while soloing; nil when not soloing.
    var soloVisibleIndices: Set<Int>? {
        soloRoot.map { isolatedVisibleIndices(of: $0) }
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
}
