import RealityKit
import SwiftUI

@Observable
@MainActor
final class HostSidebarModel: PreviewOverlay {
    var hide = Set<Int>()
    var soloRoot: Int?
    var debug: DebugMode = .none
    var activeSceneIndex: Int
    var selectedCameraIndex: Int?
    var overlayRevision = 0
    let document: GLTFSessionDocument

    @ObservationIgnored private var cachedFillMaterials: [ObjectIdentifier: [any RealityKit.Material]] = [:]
    @ObservationIgnored private var appliedRevision = Int.min

    enum DebugMode: String, CaseIterable {
        case none, baseColor, roughness, metalness, normals, emission, wireframe

        var title: String {
            switch self {
            case .none: "None"
            case .baseColor: "Base Color"
            case .roughness: "Roughness"
            case .metalness: "Metalness"
            case .normals: "Normals"
            case .emission: "Emission"
            case .wireframe: "Wireframe"
            }
        }

        var visualizationMode: ModelDebugOptionsComponent.VisualizationMode? {
            switch self {
            case .none, .wireframe: nil
            case .baseColor: .baseColor
            case .roughness: .roughness
            case .metalness: .metallic
            case .normals: .normal
            case .emission: .emissive
            }
        }
    }

    init(document: GLTFSessionDocument) {
        self.document = document
        self.activeSceneIndex = document.defaultSceneIndex
    }

    func layerRootIndices() -> [Int] {
        guard document.scenes.indices.contains(activeSceneIndex) else { return [] }
        return document.scenes[activeSceneIndex].rootNodeIndices
    }

    func showAll() {
        hide.removeAll()
        soloRoot = nil
        overlayRevision += 1
    }

    func soloHides(_ id: Int) -> Bool {
        guard let soloRoot else { return false }
        if id == soloRoot { return false }
        if ancestorIndices(of: soloRoot).contains(id) { return false }
        return layerRootIndices().contains(id)
    }

    func apply(to root: Entity) {
        appliedRevision = Int.min
        applyIfNeeded(to: root)
    }

    func applyIfNeeded(to root: Entity) {
        guard overlayRevision != appliedRevision else { return }
        appliedRevision = overlayRevision
        restoreFillMaterials(to: root)
        cachedFillMaterials.removeAll()
        applyVisibility(to: root)
        applyDebug(to: root)
    }

    private func ancestorIndices(of id: Int) -> Set<Int> {
        var found = Set<Int>()
        var current = id
        while let parent = document.nodes.first(where: { $0.children.contains(current) })?.index {
            found.insert(parent)
            current = parent
        }
        return found
    }

    private func applyVisibility(to entity: Entity) {
        if let id = entity.components[GLTFNodeIDComponent.self]?.nodeIndex {
            entity.isEnabled = !hide.contains(id) && !soloHides(id)
        }
        for child in entity.children {
            applyVisibility(to: child)
        }
    }

    private func applyDebug(to entity: Entity) {
        switch debug {
        case .none:
            break
        case .wireframe:
            applyWireframe(to: entity)
        case .baseColor, .roughness, .metalness, .normals, .emission:
            if let mode = debug.visualizationMode {
                applyDebugChannel(mode, to: entity)
            }
        }
    }

    private func applyDebugChannel(_ mode: ModelDebugOptionsComponent.VisualizationMode, to entity: Entity) {
        entity.components.set(ModelDebugOptionsComponent(visualizationMode: mode))
        for child in entity.children {
            applyDebugChannel(mode, to: child)
        }
    }

    private func applyWireframe(to entity: Entity) {
        if var model = entity.components[ModelComponent.self] {
            let id = ObjectIdentifier(entity)
            if cachedFillMaterials[id] == nil {
                cachedFillMaterials[id] = model.materials
            }
            model.materials = lineFillCopies(cachedFillMaterials[id] ?? model.materials)
            entity.components.set(model)
        }
        for child in entity.children {
            applyWireframe(to: child)
        }
    }

    private func restoreFillMaterials(to entity: Entity) {
        if var model = entity.components[ModelComponent.self] {
            let id = ObjectIdentifier(entity)
            if let materials = cachedFillMaterials[id] {
                model.materials = materials
                entity.components.set(model)
            }
        }
        entity.components.remove(ModelDebugOptionsComponent.self)
        for child in entity.children {
            restoreFillMaterials(to: child)
        }
    }

    private func lineFillCopies(_ materials: [any RealityKit.Material]) -> [any RealityKit.Material] {
        materials.map { material in
            switch material {
            case var pbr as PhysicallyBasedMaterial:
                pbr.triangleFillMode = .lines
                return pbr
            case var unlit as UnlitMaterial:
                unlit.triangleFillMode = .lines
                return unlit
            case var simple as SimpleMaterial:
                simple.triangleFillMode = .lines
                return simple
            default:
                return material
            }
        }
    }
}
