import Foundation
import RealityKit

/// Host-facing reads and writes on a loaded model, so host code never touches the entity.
extension EntityLoader.LoadedModel {
    /// Name of the converted root (the file name).
    public var name: String { entity.name }

    /// W×H×D and the visual AABB centre, both in model space. `dimensions` is nil for empty bounds.
    @MainActor
    public var extent: (dimensions: ModelDimensions?, center: SIMD3<Float>) {
        let bounds = PreviewCamera.modelBounds(of: entity, relativeTo: entity)
        return (ModelDimensions(bounds: bounds), bounds.center)
    }

    @MainActor
    public func morphTargets() -> [PreviewMorph.Target] {
        PreviewMorph.targets(in: entity)
    }

    @MainActor
    public func setMorphWeight(nodeIndex: Int, targetIndex: Int, value: Float) {
        PreviewMorph.setWeight(nodeIndex: nodeIndex, targetIndex: targetIndex, value: value, in: entity)
    }

    /// Same document, stats and reports on a newly converted scene (host scene switch).
    public func switchingScene(
        to index: Int,
        from url: URL,
        includeAnimations: Bool = true,
        materialVariantIndex: Int? = nil
    ) async throws -> EntityLoader.LoadedModel {
        let build = try await EntityLoader.convertScene(
            index: index,
            from: url,
            includeAnimations: includeAnimations,
            materialVariantIndex: materialVariantIndex
        )
        return EntityLoader.LoadedModel(
            entity: build.entity,
            stats: stats,
            document: document,
            debugModes: debugModes,
            studioIBLExponent: build.studioIBLExponent,
            pipelineReport: pipelineReport,
            convertProblems: convertProblems,
            materialVariantNames: materialVariantNames
        )
    }
}
