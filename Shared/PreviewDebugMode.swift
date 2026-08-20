import Foundation
import RealityKit

/// glTF-relevant preview debug modes. The cycle list is filtered per asset.
enum PreviewDebugMode: Equatable, Hashable {
    case none
    case wire
    case visualization(ModelDebugOptionsComponent.VisualizationMode)

    var shortTitle: String {
        switch self {
        case .none: "None"
        case .wire: "Wire"
        case .visualization(let mode):
            switch mode {
            case .normal: "Nrm"
            case .textureCoordinates: "UV"
            case .baseColor: "Base"
            case .metallic: "Met"
            case .roughness: "Rgh"
            case .ambientOcclusion: "AO"
            case .emissive: "Emit"
            case .finalAlpha: "A"
            case .specular: "Spec"
            case .tangent: "Tan"
            case .clearcoat: "Coat"
            case .clearcoatRoughness: "CoatR"
            case .clearcoatNormal: "CoatN"
            default: mode.rawValue
            }
        }
    }

    /// None is empty. Wire (first real mode) is 100%; later options count down toward 0.
    static func variableValue(index: Int, count: Int) -> Double {
        guard count > 1 else { return 0 }
        let clamped = min(max(index, 0), count - 1)
        if clamped == 0 { return 0 }
        if count == 2 { return 1 }
        return 1 - Double(clamped - 1) / Double(count - 2)
    }

    /// Modes present and used in `json`, in cycle order.
    static func available(from json: [String: Any]) -> [PreviewDebugMode] {
        let flags = Channels(json: json)
        var modes: [PreviewDebugMode] = [.none]
        if flags.hasTriangles { modes.append(.wire) }
        if flags.hasNormals { modes.append(.visualization(.normal)) }
        if flags.hasUVs { modes.append(.visualization(.textureCoordinates)) }
        if flags.hasBase { modes.append(.visualization(.baseColor)) }
        if flags.hasMetallic { modes.append(.visualization(.metallic)) }
        if flags.hasRoughness { modes.append(.visualization(.roughness)) }
        if flags.hasAO { modes.append(.visualization(.ambientOcclusion)) }
        if flags.hasEmissive { modes.append(.visualization(.emissive)) }
        if flags.hasAlpha { modes.append(.visualization(.finalAlpha)) }
        if flags.hasSpecular { modes.append(.visualization(.specular)) }
        if flags.hasTangents { modes.append(.visualization(.tangent)) }
        if flags.hasClearcoat { modes.append(.visualization(.clearcoat)) }
        if flags.hasClearcoatRoughness { modes.append(.visualization(.clearcoatRoughness)) }
        if flags.hasClearcoatNormal { modes.append(.visualization(.clearcoatNormal)) }
        return modes
    }

    static func apply(_ mode: PreviewDebugMode, to root: Entity, store: DebugMaterialStore) {
        switch mode {
        case .none:
            store.restore(root)
            clearDebug(root)
        case .wire:
            store.snapshotIfNeeded(root)
            clearDebug(root)
            applyWire(root)
        case .visualization(let visualization):
            store.restore(root)
            applyVisualization(root, visualization)
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

private struct Channels {
    var hasTriangles = false
    var hasNormals = false
    var hasUVs = false
    var hasTangents = false
    var hasBase = false
    var hasMetallic = false
    var hasRoughness = false
    var hasAO = false
    var hasEmissive = false
    var hasAlpha = false
    var hasSpecular = false
    var hasClearcoat = false
    var hasClearcoatRoughness = false
    var hasClearcoatNormal = false

    init(json: [String: Any]) {
        scanMeshes(json["meshes"] as? [[String: Any]] ?? [])
        scanMaterials(json["materials"] as? [[String: Any]] ?? [])
    }

    private mutating func scanMeshes(_ meshes: [[String: Any]]) {
        for mesh in meshes {
            for primitive in mesh["primitives"] as? [[String: Any]] ?? [] {
                let attributes = primitive["attributes"] as? [String: Any] ?? [:]
                if attributes["NORMAL"] != nil { hasNormals = true }
                if attributes["TANGENT"] != nil { hasTangents = true }
                if attributes.keys.contains(where: { $0.hasPrefix("TEXCOORD_") }) {
                    hasUVs = true
                }
                let mode = GLBBox.intValue(primitive["mode"]) ?? 4
                if mode == 4 || mode == 5 || mode == 6 {
                    hasTriangles = true
                }
            }
        }
    }

    private mutating func scanMaterials(_ materials: [[String: Any]]) {
        if !materials.isEmpty {
            hasBase = true
        }
        for material in materials {
            let extensions = material["extensions"] as? [String: Any] ?? [:]
            let unlit = extensions["KHR_materials_unlit"] != nil
            let specGloss = extensions["KHR_materials_pbrSpecularGlossiness"] != nil
            if specGloss || extensions["KHR_materials_specular"] != nil {
                hasSpecular = true
            }
            if let alpha = material["alphaMode"] as? String,
               alpha == "MASK" || alpha == "BLEND" {
                hasAlpha = true
            }
            if material["normalTexture"] != nil {
                hasNormals = true
            }
            if material["occlusionTexture"] != nil {
                hasAO = true
            }
            if material["emissiveTexture"] != nil {
                hasEmissive = true
            }
            if let emissive = float3(material["emissiveFactor"]), !nearZero(emissive) {
                hasEmissive = true
            }

            let metalRough = !unlit && !specGloss
            if metalRough {
                let pbr = material["pbrMetallicRoughness"] as? [String: Any] ?? [:]
                let hasMRTexture = pbr["metallicRoughnessTexture"] != nil
                if hasMRTexture || hasNonDefault(pbr["metallicFactor"], default: 1) {
                    hasMetallic = true
                }
                if hasMRTexture || hasNonDefault(pbr["roughnessFactor"], default: 1) {
                    hasRoughness = true
                }
            }

            if let clearcoat = extensions["KHR_materials_clearcoat"] as? [String: Any] {
                if clearcoat["clearcoatTexture"] != nil
                    || hasNonDefault(clearcoat["clearcoatFactor"], default: 0) {
                    hasClearcoat = true
                }
                if clearcoat["clearcoatRoughnessTexture"] != nil
                    || hasNonDefault(clearcoat["clearcoatRoughnessFactor"], default: 0) {
                    hasClearcoatRoughness = true
                }
                if clearcoat["clearcoatNormalTexture"] != nil {
                    hasClearcoatNormal = true
                }
            }
        }
    }

    private func hasNonDefault(_ value: Any?, default expected: Double) -> Bool {
        guard let number = GLBBox.doubleValue(value) else { return false }
        return abs(number - expected) > 0.0001
    }

    private func float3(_ value: Any?) -> SIMD3<Float>? {
        guard let values = value as? [Any], values.count >= 3 else { return nil }
        return SIMD3(
            Float(GLBBox.doubleValue(values[0]) ?? 0),
            Float(GLBBox.doubleValue(values[1]) ?? 0),
            Float(GLBBox.doubleValue(values[2]) ?? 0)
        )
    }

    private func nearZero(_ value: SIMD3<Float>) -> Bool {
        abs(value.x) < 0.0001 && abs(value.y) < 0.0001 && abs(value.z) < 0.0001
    }
}

private func applyWire(_ root: Entity) {
    visitModels(root) { entity, model in
        var next = model
        next.materials = model.materials.map(withWireframe)
        entity.components.set(next)
    }
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

private func visitModels(_ entity: Entity, _ body: (Entity, ModelComponent) -> Void) {
    if let model = entity.components[ModelComponent.self] {
        body(entity, model)
    }
    for child in entity.children {
        visitModels(child, body)
    }
}
