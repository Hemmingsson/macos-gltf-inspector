import Foundation
import RealityKit

/// Host-facing reads and writes on a loaded model, so host code never touches the entity.
extension EntityLoader.LoadedModel {
    /// Name of the converted root (the file name).
    var name: String { entity.name }

    /// W×H×D and the visual AABB centre, both in model space. `dimensions` is nil for empty bounds.
    @MainActor
    var extent: (dimensions: ModelDimensions?, center: SIMD3<Float>) {
        let bounds = PreviewCamera.modelBounds(of: entity, relativeTo: entity)
        return (ModelDimensions(bounds: bounds), bounds.center)
    }

    @MainActor
    func morphTargets() -> [PreviewMorph.Target] {
        PreviewMorph.targets(in: entity)
    }

    @MainActor
    func setMorphWeight(nodeIndex: Int, targetIndex: Int, value: Float) {
        PreviewMorph.setWeight(nodeIndex: nodeIndex, targetIndex: targetIndex, value: value, in: entity)
    }

    /// Same document, stats and reports on a newly converted scene (host scene switch).
    @MainActor
    func replacingScene(_ scene: EntityLoader.ConvertedScene) -> EntityLoader.LoadedModel {
        EntityLoader.LoadedModel(
            entity: scene.entity,
            stats: stats,
            document: document,
            debugModes: debugModes,
            studioIBLExponent: PreviewEmissive.studioIBLExponent(
                punctualLightCount: EntityLoader.punctualLightCount(in: scene.entity)
            ),
            pipelineReport: pipelineReport,
            convertProblems: convertProblems,
            materialVariantNames: materialVariantNames
        )
    }
}

extension EntityLoader {
    /// One converted scene, held opaquely until `LoadedModel.replacingScene` adopts it.
    struct ConvertedScene {
        let entity: Entity
    }

    /// `convertScene` wrapped for the host scene switch.
    static func loadScene(
        index: Int,
        from url: URL,
        materialVariantIndex: Int? = nil
    ) async throws -> ConvertedScene {
        ConvertedScene(
            entity: try await convertScene(index: index, from: url, materialVariantIndex: materialVariantIndex)
        )
    }
}
