import AppKit
import Foundation
import RealityKit

/// glTF-relevant preview debug modes. The cycle list is filtered per asset.
enum PreviewDebugMode: Equatable, Hashable {
    case none
    case wire
    /// Custom: white unlit so mesh `COLOR_*` dominates (no SDK viz mode).
    case vertexColors
    case visualization(ModelDebugOptionsComponent.VisualizationMode)

    var shortTitle: String {
        switch self {
        case .none: "None"
        case .wire: "Wire"
        case .vertexColors: "RGB"
        case .visualization(let mode): Self.labels(for: mode).title
        }
    }

    /// Stable id for seam menus (not localized). Prefer short labels over SDK rawValues.
    var channelID: String {
        switch self {
        case .none: "none"
        case .wire: "wire"
        case .vertexColors: "vertexColors"
        case .visualization(let mode): Self.labels(for: mode).id
        }
    }

    /// Modes present and used in `json`, in cycle order.
    /// `lightingDiffuse` / `lightingSpecular` are SDK cases confirmed on this macOS SDK.
    static func available(from json: [String: Any]) -> [PreviewDebugMode] {
        let flags = Channels(json: json)
        var modes: [PreviewDebugMode] = [.none]
        if flags.hasTriangles { modes.append(.wire) }

        let gated: [(Bool, ModelDebugOptionsComponent.VisualizationMode)] = [
            (flags.hasNormals, .normal),
            (flags.hasUVs, .textureCoordinates),
            (flags.hasBase, .baseColor),
            (flags.hasMetallic, .metallic),
            (flags.hasRoughness, .roughness),
            (flags.hasAO, .ambientOcclusion),
            (flags.hasEmissive, .emissive),
            (flags.hasAlpha, .finalAlpha),
            (flags.hasSpecular, .specular),
            (flags.hasTangents, .tangent),
            (flags.hasClearcoat, .clearcoat),
            (flags.hasClearcoatRoughness, .clearcoatRoughness),
            (flags.hasClearcoatNormal, .clearcoatNormal),
        ]
        for (present, mode) in gated where present {
            modes.append(.visualization(mode))
        }
        // Always useful once geometry exists — not gated on textures.
        if flags.hasTriangles {
            modes.append(.visualization(.lightingDiffuse))
            modes.append(.visualization(.lightingSpecular))
        }
        if flags.hasVertexColors { modes.append(.vertexColors) }
        return modes
    }

    /// PreviewUI `Availability.availableDebugChannels` — same filter as `available(from:)`,
    /// Sendable titles only (no RealityKit types on the seam).
    static func availableDebugChannels(from json: [String: Any]) -> [PreviewDebugChannel] {
        available(from: json).map { mode in
            PreviewDebugChannel(id: mode.channelID, title: mode.shortTitle)
        }
    }

    static func apply(_ mode: PreviewDebugMode, to root: Entity, store: DebugMaterialStore) {
        apply(mode, doubleSided: false, to: root, store: store)
    }

    /// Rebuild material overrides from the store baseline so wire + double-sided don't stack.
    /// P6 — `doubleSided` forces `faceCulling = .none`; leaving it restores via `store`.
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

    private static func labels(
        for mode: ModelDebugOptionsComponent.VisualizationMode
    ) -> (id: String, title: String) {
        switch mode {
        case .normal: ("normal", "Nrm")
        case .textureCoordinates: ("uv", "UV")
        case .baseColor: ("baseColor", "Base")
        case .metallic: ("metallic", "Met")
        case .roughness: ("roughness", "Rgh")
        case .ambientOcclusion: ("ao", "AO")
        case .emissive: ("emissive", "Emit")
        case .finalAlpha: ("alpha", "A")
        case .specular: ("specular", "Spec")
        case .tangent: ("tangent", "Tan")
        case .clearcoat: ("clearcoat", "Coat")
        case .clearcoatRoughness: ("clearcoatRoughness", "CoatR")
        case .clearcoatNormal: ("clearcoatNormal", "CoatN")
        case .lightingDiffuse: ("lightingDiffuse", "Diff")
        case .lightingSpecular: ("lightingSpecular", "LSpec")
        default: (mode.rawValue, mode.rawValue)
        }
    }
}

/// Sendable debug-channel row for PreviewUI Availability / view-mode menus.
struct PreviewDebugChannel: Identifiable, Equatable, Sendable, Hashable {
    let id: String
    let title: String
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
    var hasVertexColors = false
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
                if attributes.keys.contains(where: { $0.hasPrefix("COLOR_") }) {
                    hasVertexColors = true
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
            let maps = MaterialMapPresence.from(json: material)

            if maps.specular || extensions["KHR_materials_specular"] != nil || specGloss {
                hasSpecular = true
            }
            if let alpha = material["alphaMode"] as? String,
               alpha == "MASK" || alpha == "BLEND" {
                hasAlpha = true
            }
            if maps.normal {
                hasNormals = true
            }
            if maps.occlusion {
                hasAO = true
            }
            if maps.emissive {
                hasEmissive = true
            }
            if let emissive = float3(material["emissiveFactor"]), !nearZero(emissive) {
                hasEmissive = true
            }

            let metalRough = !unlit && !specGloss
            if metalRough {
                let pbr = material["pbrMetallicRoughness"] as? [String: Any] ?? [:]
                if maps.metallicRoughness || hasNonDefault(pbr["metallicFactor"], default: 1) {
                    hasMetallic = true
                }
                if maps.metallicRoughness || hasNonDefault(pbr["roughnessFactor"], default: 1) {
                    hasRoughness = true
                }
            }

            if maps.clearcoat {
                hasClearcoat = true
            }
            if maps.clearcoatRoughness {
                hasClearcoatRoughness = true
            }
            if maps.clearcoatNormal {
                hasClearcoatNormal = true
            }
            if let clearcoat = extensions["KHR_materials_clearcoat"] as? [String: Any] {
                if hasNonDefault(clearcoat["clearcoatFactor"], default: 0) {
                    hasClearcoat = true
                }
                if hasNonDefault(clearcoat["clearcoatRoughnessFactor"], default: 0) {
                    hasClearcoatRoughness = true
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
