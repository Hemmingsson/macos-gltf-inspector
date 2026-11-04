import Foundation
import GLTFCore
import Observation
import PreviewUI
import simd

/// Selection adapter over `HostSidebarModel`.
///
/// Node selection drives the canvas highlight via `selectedNodeIndex`. All other outliner kinds
/// live in `resourceSelection` so material/camera/… IDs are never confused with node indices.
@MainActor
@Observable
final class EngineSelectionModel: SelectionModel {
    let sidebar: HostSidebarModel
    /// Non-mesh outliner selection (material, camera, light, scene, animation, morph, skin).
    private(set) var resourceSelection: NodeID?

    init(sidebar: HostSidebarModel) {
        self.sidebar = sidebar
    }

    var selected: NodeID? {
        if let index = sidebar.selectedNodeIndex {
            return Self.nodeID(index: index, in: sidebar.document)
        }
        return resourceSelection
    }

    var detail: NodeDetail? {
        guard let id = selected else { return nil }
        return Self.detail(for: id, document: sidebar.document)
    }

    func select(_ id: NodeID?) {
        switch id?.kind {
        case .mesh, .empty:
            resourceSelection = nil
            sidebar.selectedNodeIndex = id?.index
        case .camera, .light, .skin, .material, .animation, .morph, .scene:
            sidebar.selectedNodeIndex = nil
            resourceSelection = id
        case nil:
            sidebar.selectedNodeIndex = nil
            resourceSelection = nil
        }
    }

    // MARK: - Mapping

    private static func nodeID(index: Int, in document: GLTFSessionDocument) -> NodeID? {
        guard let node = document.nodes.first(where: { $0.index == index }) else {
            return NodeID(kind: .empty, index: index)
        }
        return NodeID(kind: EngineSceneModel.nodeKind(node.kind), index: index)
    }

    static func detail(for id: NodeID, document: GLTFSessionDocument) -> NodeDetail? {
        switch id.kind {
        // Camera and light rows are scene-tree nodes, like meshes.
        case .mesh, .empty, .camera, .light:
            guard let node = document.nodes.first(where: { $0.index == id.index }) else {
                return nil
            }
            return nodeDetail(node: node, document: document)
        case .skin:
            return skinDetail(index: id.index, document: document)
        case .material:
            return materialDetail(index: id.index, document: document)
        case .animation:
            return animationDetail(index: id.index, document: document)
        case .morph:
            return morphDetail(index: id.index, document: document)
        case .scene:
            return sceneDetail(index: id.index, document: document)
        }
    }

    private static func nodeDetail(
        node: GLTFSessionDocument.Node,
        document: GLTFSessionDocument
    ) -> NodeDetail {
        let id = NodeID(kind: EngineSceneModel.nodeKind(node.kind), index: node.index)
        let euler = eulerDegrees(from: node.rotation)
        let transform = TransformInfo(
            position: Vector3(
                x: Double(node.translation.x),
                y: Double(node.translation.y),
                z: Double(node.translation.z)
            ),
            rotationDegrees: Vector3(x: Double(euler.x), y: Double(euler.y), z: Double(euler.z)),
            scale: Vector3(
                x: Double(node.scale.x),
                y: Double(node.scale.y),
                z: Double(node.scale.z)
            )
        )

        let geometry: GeometryInfo? = node.kind == .mesh
            ? GeometryInfo(
                triangleCount: node.triangleCount,
                vertexCount: node.vertexCount,
                uvSetCount: node.uvSetCount,
                hasTangents: node.hasTangents,
                hasVertexColors: node.hasVertexColors
            )
            : nil

        let material: MaterialInfo? = {
            guard node.kind == .mesh,
                  let materialIndex = node.materialIndices.first,
                  document.materials.indices.contains(materialIndex)
            else { return nil }
            return EngineSceneModel.materialInfo(index: materialIndex, document: document)
        }()

        var camera: CameraInfo?
        var light: LightInfo?
        if node.kind == .camera, let cameraIndex = node.cameraIndex {
            camera = EngineSceneModel.cameraInfo(index: cameraIndex, document: document)
        }
        if node.kind == .light, let lightIndex = node.lightIndex {
            light = EngineSceneModel.lightInfo(index: lightIndex, document: document)
        }
        var skin: SkinInfo?
        if node.kind == .skin, let skinIndex = node.skinIndex {
            skin = EngineSceneModel.skinInfo(index: skinIndex, document: document)
        }

        let name = EngineSceneModel.displayName(node.name, fallback: "Node \(node.index)")
        return NodeDetail(
            id: id,
            name: name,
            transform: transform,
            geometry: geometry,
            material: material,
            light: light,
            camera: camera,
            skin: skin
        )
    }

    private static func materialDetail(index: Int, document: GLTFSessionDocument) -> NodeDetail? {
        guard document.materials.indices.contains(index) else { return nil }
        let material = EngineSceneModel.materialInfo(index: index, document: document)
        return NodeDetail(id: material.id, name: material.name, material: material)
    }

    private static func skinDetail(index: Int, document: GLTFSessionDocument) -> NodeDetail? {
        guard let skin = EngineSceneModel.skinInfo(index: index, document: document) else {
            return nil
        }
        return NodeDetail(id: skin.id, name: skin.name, skin: skin)
    }

    private static func animationDetail(index: Int, document: GLTFSessionDocument) -> NodeDetail? {
        guard document.animations.indices.contains(index) else { return nil }
        let info = EngineSceneModel.animationInfo(document.animations[index], index: index)
        return NodeDetail(id: info.id, name: info.name, animation: info)
    }

    private static func morphDetail(index: Int, document: GLTFSessionDocument) -> NodeDetail? {
        guard document.morphs.indices.contains(index) else { return nil }
        let info = EngineSceneModel.morphInfo(document.morphs[index], index: index)
        return NodeDetail(id: info.id, name: info.meshName, morph: info)
    }

    private static func sceneDetail(index: Int, document: GLTFSessionDocument) -> NodeDetail? {
        guard document.scenes.indices.contains(index) else { return nil }
        let scene = document.scenes[index]
        return NodeDetail(
            id: NodeID(kind: .scene, index: index),
            name: EngineSceneModel.sceneName(scene, index: index),
            sceneRootCount: scene.rootNodeIndices.count
        )
    }
}

/// Intrinsic XYZ Euler degrees from a unit quaternion (matches glTF TRS authoring).
private func eulerDegrees(from q: simd_quatf) -> SIMD3<Float> {
    let x = q.imag.x
    let y = q.imag.y
    let z = q.imag.z
    let w = q.real

    let sinr = 2 * (w * x + y * z)
    let cosr = 1 - 2 * (x * x + y * y)
    let roll = atan2(sinr, cosr)

    let sinp = 2 * (w * y - z * x)
    let pitch: Float
    if abs(sinp) >= 1 {
        pitch = copysign(.pi / 2, sinp)
    } else {
        pitch = asin(sinp)
    }

    let siny = 2 * (w * z + x * y)
    let cosy = 1 - 2 * (y * y + z * z)
    let yaw = atan2(siny, cosy)

    let toDeg: Float = 180 / .pi
    return SIMD3(roll * toDeg, pitch * toDeg, yaw * toDeg)
}
