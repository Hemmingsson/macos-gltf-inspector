import AppKit
import Foundation
import GLTFCore
import RealityKit

/// glTF-relevant preview debug modes. The cycle list is filtered per asset.
public enum PreviewDebugMode: Equatable, Hashable {
    case none
    case wire
    /// Custom: white unlit so mesh `COLOR_*` dominates (no SDK viz mode).
    case vertexColors
    case visualization(ModelDebugOptionsComponent.VisualizationMode)

    /// Renderer-neutral reading. Vertex colours and SDK modes with no glTF channel read as shaded.
    public var renderViewMode: RenderViewMode {
        switch self {
        case .none, .vertexColors: .shaded
        case .wire: .wireframe
        case .visualization(let mode): Self.channel(for: mode).map { .channel($0) } ?? .shaded
        }
    }

    static func channel(
        for visualization: ModelDebugOptionsComponent.VisualizationMode
    ) -> RenderViewMode.Channel? {
        switch visualization {
        case .baseColor: .baseColor
        case .metallic: .metallic
        case .roughness: .roughness
        case .normal: .normals
        case .tangent: .tangents
        case .textureCoordinates: .textureCoordinates
        case .ambientOcclusion: .ambientOcclusion
        case .emissive: .emissive
        case .finalAlpha: .alpha
        case .specular: .specular
        case .clearcoat: .clearcoat
        case .clearcoatRoughness: .clearcoatRoughness
        case .clearcoatNormal: .clearcoatNormal
        default: nil
        }
    }

    /// Modes present and used in `json`, in cycle order: the file's channels
    /// (`ViewModeAvailability`, shared with the web path) plus RealityKit-only extras.
    /// `lightingDiffuse` / `lightingSpecular` are SDK cases confirmed on this macOS SDK.
    static func available(from json: [String: Any]) -> [PreviewDebugMode] {
        let flags = ViewModeAvailability(json: json)
        var modes: [PreviewDebugMode] = [.none]
        if flags.hasTriangles { modes.append(.wire) }
        modes += flags.channels.map { .visualization(visualization(for: $0)) }
        // Always useful once geometry exists — not gated on textures.
        if flags.hasTriangles {
            modes.append(.visualization(.lightingDiffuse))
            modes.append(.visualization(.lightingSpecular))
        }
        if flags.hasVertexColors { modes.append(.vertexColors) }
        return modes
    }

    static func visualization(
        for channel: RenderViewMode.Channel
    ) -> ModelDebugOptionsComponent.VisualizationMode {
        switch channel {
        case .baseColor: .baseColor
        case .metallic: .metallic
        case .roughness: .roughness
        case .normals: .normal
        case .tangents: .tangent
        case .textureCoordinates: .textureCoordinates
        case .ambientOcclusion: .ambientOcclusion
        case .emissive: .emissive
        case .alpha: .finalAlpha
        case .specular: .specular
        case .clearcoat: .clearcoat
        case .clearcoatRoughness: .clearcoatRoughness
        case .clearcoatNormal: .clearcoatNormal
        }
    }

    static func apply(_ mode: PreviewDebugMode, to root: Entity, store: DebugMaterialStore) {
        apply(mode, doubleSided: false, to: root, store: store)
    }

    /// Rebuild material overrides from the store baseline so wire + double-sided don't stack.
    /// `doubleSided` forces `faceCulling = .none`; leaving it restores via `store`.
    static func apply(
        _ mode: PreviewDebugMode,
        doubleSided: Bool,
        to root: Entity,
        store: DebugMaterialStore
    ) {
        store.restore(root)
        clearDebug(root)

        switch mode {
        case .none:
            break
        case .wire:
            store.snapshotIfNeeded(root)
            applyWire(root)
        case .vertexColors:
            store.snapshotIfNeeded(root)
            applyVertexColors(root)
        case .visualization(let visualization):
            applyVisualization(root, visualization)
        }

        if doubleSided {
            store.snapshotIfNeeded(root)
            applyDoubleSided(root)
        }
    }
}

/// Original materials so wireframe can be undone.
final class DebugMaterialStore {
    private var snapshots: [ObjectIdentifier: [any RealityKit.Material]] = [:]

    func snapshotIfNeeded(_ root: Entity) {
        visit(root) { entity in
            guard let model = entity.components[ModelComponent.self] else { return }
            let id = ObjectIdentifier(entity)
            if snapshots[id] == nil {
                snapshots[id] = model.materials
            }
        }
    }

    func restore(_ root: Entity) {
        visit(root) { entity in
            let id = ObjectIdentifier(entity)
            guard var model = entity.components[ModelComponent.self],
                  let materials = snapshots[id]
            else { return }
            model.materials = materials
            entity.components.set(model)
        }
    }

    private func visit(_ entity: Entity, _ body: (Entity) -> Void) {
        body(entity)
        for child in entity.children {
            visit(child, body)
        }
    }
}

private func applyWire(_ root: Entity) {
    mapModelMaterials(root) { withWireframe($0) }
}

/// White unlit so authored mesh colors (when converted) show without textures/lighting.
private func applyVertexColors(_ root: Entity) {
    mapModelMaterials(root) { _ in UnlitMaterial(color: NSColor.white) }
}

private func applyDoubleSided(_ root: Entity) {
    mapModelMaterials(root) { withDoubleSided($0) }
}

private func applyVisualization(
    _ root: Entity,
    _ mode: ModelDebugOptionsComponent.VisualizationMode
) {
    visitModels(root) { entity, _ in
        entity.components.set(ModelDebugOptionsComponent(visualizationMode: mode))
    }
}

private func clearDebug(_ root: Entity) {
    visitModels(root) { entity, _ in
        entity.components.remove(ModelDebugOptionsComponent.self)
    }
}

private func mapModelMaterials(
    _ root: Entity,
    _ transform: (any RealityKit.Material) -> any RealityKit.Material
) {
    visitModels(root) { entity, model in
        var next = model
        next.materials = model.materials.map(transform)
        entity.components.set(next)
    }
}

private func withWireframe(_ material: any RealityKit.Material) -> any RealityKit.Material {
    if var pbr = material as? PhysicallyBasedMaterial {
        pbr.triangleFillMode = .lines
        return pbr
    }
    if var unlit = material as? UnlitMaterial {
        unlit.triangleFillMode = .lines
        return unlit
    }
    if var simple = material as? SimpleMaterial {
        simple.triangleFillMode = .lines
        return simple
    }
    return material
}

private func withDoubleSided(_ material: any RealityKit.Material) -> any RealityKit.Material {
    if var pbr = material as? PhysicallyBasedMaterial {
        pbr.faceCulling = .none
        return pbr
    }
    if var unlit = material as? UnlitMaterial {
        unlit.faceCulling = .none
        return unlit
    }
    if var simple = material as? SimpleMaterial {
        simple.faceCulling = .none
        return simple
    }
    return material
}

private func visitModels(_ entity: Entity, _ body: (Entity, ModelComponent) -> Void) {
    if let model = entity.components[ModelComponent.self] {
        body(entity, model)
    }
    for child in entity.children {
        visitModels(child, body)
    }
}
