import GLTFCore
import simd

/// Dimensions readout sizing for the canvas overlay.
@MainActor
enum SelectionDimensions {
    static func readout(view: ViewState, fileBounds: ModelBounds?) -> (size: SIMD3<Float>, name: String?) {
        let nodes = view.selectedSceneNodes
        if nodes.count > 1 {
            var unionMin = SIMD3<Float>(repeating: .infinity)
            var unionMax = SIMD3<Float>(repeating: -.infinity)
            for index in nodes {
                guard let box = view.canvas.bounds(ofNode: index) else { continue }
                unionMin = min(unionMin, box.min)
                unionMax = max(unionMax, box.max)
            }
            if unionMin.x.isFinite {
                return (unionMax - unionMin, multiSelectionName(view: view))
            }
        }
        if let id = view.selection, id.kind.isSceneNode,
           let size = sizedMeshNode(view: view, nodeIndex: id.index), size.max() > 0 {
            return (size, view.document.displayName(of: id))
        }
        return (fileBounds?.size ?? .zero, nil)
    }

    private static func multiSelectionName(view: ViewState) -> String? {
        view.selectedIDs.count > 1 ? "\(view.selectedIDs.count) selected" : view.selection.flatMap { view.document.displayName(of: $0) }
    }

    private static func sizedMeshNode(view: ViewState, nodeIndex: Int) -> SIMD3<Float>? {
        guard let local = view.canvas.localMeshSize(ofNode: nodeIndex) else {
            guard let box = view.canvas.bounds(ofNode: nodeIndex) else { return nil }
            return box.max - box.min
        }
        guard let scale = view.canvas.worldScale(ofNode: nodeIndex) else { return local }
        return local * scale
    }
}
