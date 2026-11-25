import Foundation

/// The window's hide, solo and isolate options resolved against one scene. Node subtrees are
/// tested through `MetalScene.ancestors(ofNode:)`, which includes the node itself.
struct MetalDrawFilter: Equatable {
    var hidden: Set<Int> = []
    var solo: Set<Int> = []
    var isolated: Int?

    init(_ options: ViewOptions) {
        hidden = options.hiddenNodeIndices
        solo = options.soloNodeIndices
        isolated = options.isolatedNodeIndex
    }

    var isEmpty: Bool { hidden.isEmpty && solo.isEmpty && isolated == nil }

    /// One Bool per `scene.draws` entry.
    func visibleDraws(in scene: MetalScene) -> [Bool] {
        // An isolated mesh node with its own draws hides its children's meshes too.
        let isolatedHasDraws = isolated.map { node in scene.draws.contains { $0.nodeIndex == node } } ?? false
        return scene.draws.map { draw in
            let chain = scene.ancestors(ofNode: draw.nodeIndex)
            if chain.contains(where: { hidden.contains($0) }) { return false }
            if !solo.isEmpty && !chain.contains(where: { solo.contains($0) }) { return false }
            if let isolated {
                return isolatedHasDraws ? draw.nodeIndex == isolated : chain.contains(isolated)
            }
            return true
        }
    }

    /// The scene's lights minus those under a hidden node. Solo and isolation leave lights alone.
    func visibleLights(in scene: MetalScene) -> [MetalPunctualLight] {
        guard !hidden.isEmpty else { return scene.lights }
        return scene.lights.filter { light in
            !scene.ancestors(ofNode: light.nodeIndex).contains { hidden.contains($0) }
        }
    }
}
