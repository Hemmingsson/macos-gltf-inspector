import Foundation
import Observation
import simd

/// Selection / visibility / isolation adapter over `HostSidebarModel`.
///
/// Mesh selection drives canvas highlight via `selectedNodeIndex`. All other outliner kinds
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

    var isolated: NodeID? {
        guard let index = sidebar.soloRoot else { return nil }
        return Self.nodeID(index: index, in: sidebar.document)
    }

    var detail: NodeDetail? {
        guard let id = selected else { return nil }
        return Self.detail(for: id, document: sidebar.document)
    }

    func select(_ id: NodeID?) {
        guard let id else {
            clearMeshSelection()
            resourceSelection = nil
            return
        }
        switch id.kind {
        case .mesh, .empty:
            resourceSelection = nil
            setMeshSelection(id.index)
        case .camera, .light, .skin, .material, .animation, .morph, .scene:
            clearMeshSelection()
            resourceSelection = id
        }
    }

    func isolate(_ id: NodeID?) {
        let target = Self.meshNodeIndex(id)
        let current = sidebar.soloRoot
        if target == current { return }
        if let target {
            if current != target {
                sidebar.isolate(target)
            }
        } else if let current {
            sidebar.isolate(current)
        }
    }

    func setVisible(_ id: NodeID, _ isVisible: Bool) {
        guard let index = Self.meshNodeIndex(id) else { return }
        if isVisible {
            sidebar.hide.remove(index)
        } else {
            sidebar.hide.insert(index)
        }
        sidebar.overlayRevision += 1
    }

    func isVisible(_ id: NodeID) -> Bool {
        guard let index = Self.meshNodeIndex(id) else { return true }
        return !sidebar.hide.contains(index) && !sidebar.soloHides(index)
    }

    // MARK: - Mesh selection (set semantics)

    private func setMeshSelection(_ index: Int) {
        guard sidebar.selectedNodeIndex != index else { return }
        sidebar.selectedNodeIndex = index
        sidebar.overlayRevision += 1
    }

    private func clearMeshSelection() {
        guard sidebar.selectedNodeIndex != nil else { return }
        sidebar.selectedNodeIndex = nil
        sidebar.overlayRevision += 1
    }

    // MARK: - Mapping

    /// Only scene-graph nodes participate in canvas highlight / visibility.
    private static func meshNodeIndex(_ id: NodeID?) -> Int? {
        guard let id else { return nil }
        switch id.kind {
        case .mesh, .empty:
            return id.index
        case .scene, .material, .animation, .morph, .camera, .light, .skin:
            return nil
        }
    }

    private static func nodeID(index: Int, in document: GLTFSessionDocument) -> NodeID? {
        guard let node = document.nodes.first(where: { $0.index == index }) else {
            return NodeID(kind: .empty, index: index)
        }
        return NodeID(kind: mapNodeKind(node.kind), index: index)
    }

    private static func mapNodeKind(_ kind: GLTFSessionDocument.Node.Kind) -> NodeKind {
        switch kind {
        case .empty: .empty
        case .mesh: .mesh
        case .camera: .camera
        case .light: .light
        case .skin: .skin
        }
    }

    static func detail(for id: NodeID, document: GLTFSessionDocument) -> NodeDetail? {
        switch id.kind {
        case .mesh, .empty:
            guard let node = document.nodes.first(where: { $0.index == id.index }) else {
                return nil
            }
            return nodeDetail(node: node, document: document)
        case .camera:
            return cameraDetail(index: id.index, document: document)
        case .light:
            return lightDetail(index: id.index, document: document)
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
        let id = NodeID(kind: mapNodeKind(node.kind), index: node.index)
        let transform = TransformInfo(
            position: Vector3(
                x: Double(node.translation.x),
                y: Double(node.translation.y),
                z: Double(node.translation.z)
            ),
            rotationDegrees: Vector3(
                x: Double(eulerDegrees(from: node.rotation).x),
                y: Double(eulerDegrees(from: node.rotation).y),
                z: Double(eulerDegrees(from: node.rotation).z)
            ),
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
                hasNormals: node.hasNormals,
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

        let name = node.name.isEmpty ? "Node \(node.index)" : node.name
        return NodeDetail(
            id: id,
            name: name,
            transform: transform,
            isTransformAuthored: true,
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

    private static func cameraDetail(index: Int, document: GLTFSessionDocument) -> NodeDetail? {
        guard let camera = EngineSceneModel.cameraInfo(index: index, document: document) else {
            return nil
        }
        return NodeDetail(id: camera.id, name: camera.name, camera: camera)
    }

    private static func lightDetail(index: Int, document: GLTFSessionDocument) -> NodeDetail? {
        guard let light = EngineSceneModel.lightInfo(index: index, document: document) else {
            return nil
        }
        return NodeDetail(id: light.id, name: light.name, light: light)
    }

    private static func skinDetail(index: Int, document: GLTFSessionDocument) -> NodeDetail? {
        guard let skin = EngineSceneModel.skinInfo(index: index, document: document) else {
            return nil
        }
        return NodeDetail(id: skin.id, name: skin.name, skin: skin)
    }

    private static func animationDetail(index: Int, document: GLTFSessionDocument) -> NodeDetail? {
        guard document.animations.indices.contains(index) else { return nil }
        let animation = document.animations[index]
        let trimmed = animation.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "Clip \(index + 1)" : trimmed
        let info = AnimationInfo(index: index, name: name, duration: animation.duration)
        return NodeDetail(id: info.id, name: info.name, animation: info)
    }

    private static func morphDetail(index: Int, document: GLTFSessionDocument) -> NodeDetail? {
        guard document.morphs.indices.contains(index) else { return nil }
        let morph = document.morphs[index]
        let meshName = morph.meshName.isEmpty ? "Mesh \(morph.meshIndex)" : morph.meshName
        let info = MorphInfo(index: index, meshName: meshName, targetNames: morph.targetNames)
        return NodeDetail(id: info.id, name: info.meshName, morph: info)
    }

    private static func sceneDetail(index: Int, document: GLTFSessionDocument) -> NodeDetail? {
        guard document.scenes.indices.contains(index) else { return nil }
        let scene = document.scenes[index]
        let name = scene.name.isEmpty ? "Scene \(index)" : scene.name
        return NodeDetail(
            id: NodeID(kind: .scene, index: index),
            name: name,
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
