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

    /// Rebuild material overrides from the store baseline so wire + double-sided don't stack.
    /// `doubleSided` forces `faceCulling = .none`; leaving it restores via `store`.
    static func apply(
        _ mode: PreviewDebugMode,
        doubleSided: Bool,
        to root: Entity,
        store: DebugMaterialStore
    ) {
        let models = store.models(in: root)
        if store.lastMutatedMaterials {
            store.restore(models)
        }

        let visualization: ModelDebugOptionsComponent.VisualizationMode?
        if case .visualization(let next) = mode {
            visualization = next
        } else {
            visualization = nil
        }
        applyDebugComponents(models, visualization: visualization)

        let mutates = mutatesMaterials(mode, doubleSided: doubleSided)
        if mutates {
            store.snapshotIfNeeded(models)
            switch mode {
            case .vertexColors:
                var shared: any RealityKit.Material = store.sharedVertexColorMaterial
                if doubleSided {
                    shared = withDoubleSided(shared)
                }
                store.lastUniqueTransformedCount = assignSharedMaterial(models, shared)
            case .wire, .none, .visualization:
                store.lastUniqueTransformedCount = mapModelMaterials(models, store: store) { material in
                    var next = material
                    if case .wire = mode {
                        next = withWireframe(next)
                    }
                    if doubleSided {
                        next = withDoubleSided(next)
                    }
                    return next
                }
            }
        } else {
            store.lastUniqueTransformedCount = 0
        }
        store.lastMutatedMaterials = mutates
    }

    private static func mutatesMaterials(_ mode: PreviewDebugMode, doubleSided: Bool) -> Bool {
        switch mode {
        case .wire, .vertexColors: true
        case .none, .visualization: doubleSided
        }
    }
}

/// Original materials so wireframe can be undone. Collects the model list once.
final class DebugMaterialStore {
    private var snapshots: [ObjectIdentifier: [any RealityKit.Material]] = [:]
    private var snapshotIDs: [ObjectIdentifier: [Int]] = [:]
    private var uniqueKeys: [MaterialKey] = []
    private var cachedModels: [Entity] = []
    private var didCollect = false
    /// How many times `restore` ran. Channel↔channel must not increment this.
    private(set) var restoreCount = 0
    /// Distinct transformed materials produced by the last material-mutating apply.
    var lastUniqueTransformedCount = 0
    var lastMutatedMaterials = false
    let sharedVertexColorMaterial = UnlitMaterial(color: NSColor.white)

    func models(in root: Entity) -> [Entity] {
        if !didCollect {
            cachedModels = []
            collectModels(root, into: &cachedModels)
            didCollect = true
        }
        return cachedModels
    }

    func snapshotIfNeeded(_ models: [Entity]) {
        for entity in models {
            let id = ObjectIdentifier(entity)
            guard snapshots[id] == nil, let model = entity.components[ModelComponent.self] else {
                continue
            }
            snapshots[id] = model.materials
            snapshotIDs[id] = model.materials.map { uniqueID(for: $0) }
        }
    }

    func restore(_ models: [Entity]) {
        restoreCount += 1
        for entity in models {
            let id = ObjectIdentifier(entity)
            guard var model = entity.components[ModelComponent.self],
                  let materials = snapshots[id]
            else { continue }
            model.materials = materials
            entity.components.set(model)
        }
    }

    func originalMaterials(for entity: Entity) -> [any RealityKit.Material]? {
        snapshots[ObjectIdentifier(entity)]
    }

    func materialIDs(for entity: Entity) -> [Int]? {
        snapshotIDs[ObjectIdentifier(entity)]
    }

    func uniqueID(for material: any RealityKit.Material) -> Int {
        let key = MaterialKey(material)
        if let index = uniqueKeys.firstIndex(of: key) {
            return index
        }
        uniqueKeys.append(key)
        return uniqueKeys.count - 1
    }
}

private func collectModels(_ entity: Entity, into models: inout [Entity]) {
    if entity.components[ModelComponent.self] != nil {
        models.append(entity)
    }
    for child in entity.children {
        collectModels(child, into: &models)
    }
}

private func applyDebugComponents(
    _ models: [Entity],
    visualization: ModelDebugOptionsComponent.VisualizationMode?
) {
    for entity in models {
        if let visualization {
            entity.components.set(ModelDebugOptionsComponent(visualizationMode: visualization))
        } else {
            entity.components.remove(ModelDebugOptionsComponent.self)
        }
    }
}

@discardableResult
private func assignSharedMaterial(
    _ models: [Entity],
    _ material: any RealityKit.Material
) -> Int {
    for entity in models {
        guard var model = entity.components[ModelComponent.self] else { continue }
        model.materials = Array(repeating: material, count: model.materials.count)
        entity.components.set(model)
    }
    return 1
}

@discardableResult
private func mapModelMaterials(
    _ models: [Entity],
    store: DebugMaterialStore,
    transform: (any RealityKit.Material) -> any RealityKit.Material
) -> Int {
    var cache: [Int: any RealityKit.Material] = [:]
    for entity in models {
        guard var model = entity.components[ModelComponent.self] else { continue }
        let source = store.originalMaterials(for: entity) ?? model.materials
        let ids = store.materialIDs(for: entity) ?? source.map { store.uniqueID(for: $0) }
        model.materials = zip(source, ids).map { material, id in
            if let cached = cache[id] { return cached }
            let mapped = transform(material)
            cache[id] = mapped
            return mapped
        }
        entity.components.set(model)
    }
    return cache.count
}

/// Identity for convert-shared materials (value types). Textures are class
/// instances; scalars + resource ids distinguish glTF materials without Equatable.
private struct MaterialKey: Hashable {
    var kind: UInt8
    var fill: Int
    var cull: Int
    var floats: [Float]
    var textures: [ObjectIdentifier]

    init(_ material: any RealityKit.Material) {
        if let pbr = material as? PhysicallyBasedMaterial {
            kind = 1
            fill = fillCode(pbr.triangleFillMode)
            cull = cullCode(pbr.faceCulling)
            let tint = pbr.baseColor.tint
            floats = [
                Float(tint.redComponent),
                Float(tint.greenComponent),
                Float(tint.blueComponent),
                Float(tint.alphaComponent),
                pbr.metallic.scale,
                pbr.roughness.scale,
                pbr.emissiveIntensity,
                pbr.clearcoat.scale,
                pbr.clearcoatRoughness.scale,
                pbr.specular.scale,
                pbr.opacityThreshold ?? -1,
            ]
            textures = [
                textureID(pbr.baseColor.texture),
                textureID(pbr.metallic.texture),
                textureID(pbr.roughness.texture),
                textureID(pbr.normal.texture),
                textureID(pbr.emissiveColor.texture),
                textureID(pbr.ambientOcclusion.texture),
                textureID(pbr.clearcoat.texture),
                textureID(pbr.clearcoatRoughness.texture),
                textureID(pbr.specular.texture),
            ].compactMap { $0 }
            return
        }
        if let unlit = material as? UnlitMaterial {
            kind = 2
            fill = fillCode(unlit.triangleFillMode)
            cull = cullCode(unlit.faceCulling)
            let tint = unlit.color.tint
            floats = [
                Float(tint.redComponent),
                Float(tint.greenComponent),
                Float(tint.blueComponent),
                Float(tint.alphaComponent),
                unlit.opacityThreshold ?? -1,
            ]
            textures = [textureID(unlit.color.texture)].compactMap { $0 }
            return
        }
        if let simple = material as? SimpleMaterial {
            kind = 3
            fill = fillCode(simple.triangleFillMode)
            cull = cullCode(simple.faceCulling)
            let tint = simple.color.tint
            floats = [
                Float(tint.redComponent),
                Float(tint.greenComponent),
                Float(tint.blueComponent),
                Float(tint.alphaComponent),
            ]
            textures = [textureID(simple.color.texture)].compactMap { $0 }
            return
        }
        kind = 0
        fill = 0
        cull = 0
        floats = []
        textures = []
    }
}

private func textureID(_ texture: PhysicallyBasedMaterial.Texture?) -> ObjectIdentifier? {
    texture.map { ObjectIdentifier($0.resource) }
}

private func fillCode(_ fill: MaterialParameterTypes.TriangleFillMode) -> Int {
    switch fill {
    case .lines: 1
    default: 0
    }
}

private func cullCode(_ cull: MaterialParameterTypes.FaceCulling) -> Int {
    switch cull {
    case .front: 1
    case .none: 2
    default: 0
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
