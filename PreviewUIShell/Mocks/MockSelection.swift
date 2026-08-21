import Foundation
import Observation

/// The shell's `SelectionModel`: selection, per-node visibility and isolation for one window.
///
/// Backed by the window's `MockScene` rather than a frozen copy, so a Debug-menu flag flip
/// (Slice 6) is reflected in `detail` without anything having to re-wire the selection.
@MainActor
@Observable
final class MockSelection: SelectionModel {
    /// `private(set)` satisfies the protocol's `{ get }` while keeping every mutation on a named
    /// method — the sidebar cannot quietly assign a selection that skips the isolation rules.
    private(set) var selected: NodeID?
    private(set) var isolated: NodeID?

    /// Hidden rather than visible, so a node the fixture has never heard of defaults to visible.
    private var hidden: Set<NodeID> = []
    private let scene: MockScene

    init(scene: MockScene, selected: NodeID? = nil) {
        self.scene = scene
        self.selected = selected
    }

    /// What the inspector shows for the current selection.
    ///
    /// Mesh rows invent TRS + geometry (fixtures have no authored per-node numbers yet) and bind
    /// a material by mesh index. Selecting a material / light / camera / animation row surfaces
    /// that record alone — fields the kind does not have stay nil so the inspector hides them.
    var detail: NodeDetail? {
        guard let id = selected else { return nil }
        let model = scene.model
        let resolvedName = name(of: id, in: model) ?? id.kind.rawValue.capitalized

        switch id.kind {
        case .mesh:
            return NodeDetail(
                id: id,
                name: resolvedName,
                transform: meshTransform(id),
                isTransformAuthored: true,
                geometry: meshGeometry(id),
                material: meshMaterial(id, in: model)
            )
        case .material:
            return NodeDetail(
                id: id,
                name: resolvedName,
                material: model.materials.first { $0.id == id }
            )
        case .light:
            return NodeDetail(
                id: id,
                name: resolvedName,
                transform: .identity,
                light: model.lights.first { $0.id == id }
            )
        case .camera:
            return NodeDetail(
                id: id,
                name: resolvedName,
                transform: .identity,
                camera: model.cameras.first { $0.id == id }
            )
        case .animation:
            return NodeDetail(
                id: id,
                name: resolvedName,
                animation: model.animations.first { $0.id == id }
            )
        case .scene, .skin, .morph, .empty:
            return NodeDetail(id: id, name: resolvedName, transform: .identity)
        }
    }

    func select(_ id: NodeID?) {
        selected = id
    }

    func setVisible(_ id: NodeID, _ isVisible: Bool) {
        if isVisible {
            hidden.remove(id)
        } else {
            hidden.insert(id)
        }
    }

    func isVisible(_ id: NodeID) -> Bool {
        !hidden.contains(id)
    }

    func isolate(_ id: NodeID?) {
        isolated = id
    }

    /// `NodeID` is namespaced by kind, so exactly one of these arrays can match.
    private func name(of id: NodeID, in model: MockSceneModel) -> String? {
        switch id.kind {
        case .scene: model.scenes.first { $0.id == id }?.name
        case .camera: model.cameras.first { $0.id == id }?.name
        case .light: model.lights.first { $0.id == id }?.name
        case .material: model.materials.first { $0.id == id }?.name
        case .animation: model.animations.first { $0.id == id }?.name
        case .skin: model.skins.first { $0.id == id }?.name
        case .morph: model.morphs.first { $0.id == id }?.meshName
        case .mesh, .empty: model.node(id)?.name
        }
    }

    /// Inspect-html Body numbers for mesh 0; children sit at identity so the section still shows.
    private func meshTransform(_ id: NodeID) -> TransformInfo {
        switch id.index {
        case 0:
            TransformInfo(
                position: Vector3(x: 0.42, y: 0.71, z: -0.10),
                rotationDegrees: .zero,
                scale: .one
            )
        default:
            .identity
        }
    }

    /// Invented per-mesh counts that sum near `MockScene.stats` (Body dominates).
    private func meshGeometry(_ id: NodeID) -> GeometryInfo {
        switch id.index {
        case 0:
            GeometryInfo(triangleCount: 4_212, vertexCount: 2_145, uvSetCount: 1, hasTangents: false)
        case 1:
            GeometryInfo(triangleCount: 860, vertexCount: 512, uvSetCount: 1)
        case 2:
            GeometryInfo(triangleCount: 1_240, vertexCount: 720, uvSetCount: 1)
        default:
            GeometryInfo(triangleCount: 100, vertexCount: 80)
        }
    }

    /// Body / Beak → Duck_Mat; Eyes → Eye_Mat.
    private func meshMaterial(_ id: NodeID, in model: MockSceneModel) -> MaterialInfo? {
        let materialIndex = (id.index == 1) ? 1 : 0
        return model.materials.first { $0.id == NodeID(kind: .material, index: materialIndex) }
    }
}
