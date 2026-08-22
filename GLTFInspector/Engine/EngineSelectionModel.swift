import Foundation
import Observation
import simd

/// Selection / visibility / isolation adapter over `HostSidebarModel` + `SelectionDetail`.
///
/// Host `selectNode` / `isolate` toggle; seam `select` / `isolate` are set-with-nil-to-clear —
/// call the host toggle only when the target value differs.
@MainActor
@Observable
final class EngineSelectionModel: SelectionModel {
    let sidebar: HostSidebarModel

    init(sidebar: HostSidebarModel) {
        self.sidebar = sidebar
    }

    var selected: NodeID? {
        guard let index = sidebar.selectedNodeIndex else { return nil }
        return Self.nodeID(index: index, in: sidebar.document)
    }

    var isolated: NodeID? {
        guard let index = sidebar.soloRoot else { return nil }
        return Self.nodeID(index: index, in: sidebar.document)
    }

    var detail: NodeDetail? {
        guard let index = sidebar.selectedNodeIndex,
              let resolved = SelectionDetail.resolve(nodeIndex: index, in: sidebar.document)
        else { return nil }
        return Self.nodeDetail(from: resolved, nodeIndex: index, document: sidebar.document)
    }

    func select(_ id: NodeID?) {
        let target = Self.nodeIndex(id)
        let current = sidebar.selectedNodeIndex
        if target == current { return }
        if let target {
            if current != target {
                // Selecting a different node: one toggle sets it (host clears only on same id).
                sidebar.selectNode(target)
            }
        } else if let current {
            sidebar.selectNode(current)
        }
    }

    func isolate(_ id: NodeID?) {
        let target = Self.nodeIndex(id)
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
        guard let index = Self.nodeIndex(id) else { return }
        if isVisible {
            sidebar.hide.remove(index)
        } else {
            sidebar.hide.insert(index)
        }
        sidebar.overlayRevision += 1
    }

    func isVisible(_ id: NodeID) -> Bool {
        guard let index = Self.nodeIndex(id) else { return true }
        return !sidebar.hide.contains(index) && !sidebar.soloHides(index)
    }

    // MARK: - Mapping

    private static func nodeIndex(_ id: NodeID?) -> Int? {
        guard let id else { return nil }
        switch id.kind {
        case .mesh, .empty, .camera, .light, .skin:
            return id.index
        case .scene, .material, .animation, .morph:
            return nil
        }
    }

    private static func nodeID(index: Int, in document: GLTFSessionDocument) -> NodeID? {
        guard let node = document.nodes.first(where: { $0.index == index }) else {
            return NodeID(kind: .empty, index: index)
        }
        let kind: NodeKind
        switch node.kind {
        case .empty: kind = .empty
        case .mesh: kind = .mesh
        case .camera: kind = .camera
        case .light: kind = .light
        case .skin: kind = .skin
        }
        return NodeID(kind: kind, index: index)
    }

    private static func nodeDetail(
        from detail: SelectionDetail,
        nodeIndex: Int,
        document: GLTFSessionDocument
    ) -> NodeDetail {
        let id = nodeID(index: nodeIndex, in: document) ?? NodeID(kind: .empty, index: nodeIndex)
        let transform = TransformInfo(
            position: Vector3(
                x: Double(detail.translation.x),
                y: Double(detail.translation.y),
                z: Double(detail.translation.z)
            ),
            rotationDegrees: Vector3(
                x: Double(detail.rotationEulerDegrees.x),
                y: Double(detail.rotationEulerDegrees.y),
                z: Double(detail.rotationEulerDegrees.z)
            ),
            scale: Vector3(
                x: Double(detail.scale.x),
                y: Double(detail.scale.y),
                z: Double(detail.scale.z)
            )
        )

        let material: MaterialInfo? = {
            guard let node = document.nodes.first(where: { $0.index == nodeIndex }),
                  let materialIndex = node.materialIndices.first,
                  document.materials.indices.contains(materialIndex)
            else { return nil }
            return materialInfo(index: materialIndex, document: document)
        }()

        let camera: CameraInfo? = detail.camera.map { fields in
            let projection: Projection =
                fields.type.lowercased().contains("orthographic") ? .orthographic : .perspective
            return CameraInfo(
                index: nodeIndex,
                name: detail.name,
                projection: projection,
                fieldOfViewDegrees: fields.yfovDegrees.map(Double.init),
                zNear: Double(fields.znear),
                zFar: fields.zfar.map(Double.init)
            )
        }

        let light: LightInfo? = detail.light.map { fields in
            let kind: LightInfo.Kind
            switch fields.type.lowercased() {
            case "directional": kind = .directional
            case "spot": kind = .spot
            default: kind = .point
            }
            return LightInfo(
                index: nodeIndex,
                name: detail.name,
                kind: kind,
                color: RGBColor(
                    red: Double(fields.color.x),
                    green: Double(fields.color.y),
                    blue: Double(fields.color.z)
                ),
                intensity: Double(fields.intensity),
                range: fields.range.map(Double.init)
            )
        }

        // Per-node triangle/vertex counts are not on `GLTFSessionDocument` yet — chips only.
        return NodeDetail(
            id: id,
            name: detail.name,
            transform: transform,
            isTransformAuthored: true,
            geometry: nil,
            material: material,
            light: light,
            camera: camera
        )
    }

    private static func materialInfo(index: Int, document: GLTFSessionDocument) -> MaterialInfo {
        let material = document.materials[index]
        let workflow: MaterialInfo.Workflow
        switch material.workflow {
        case .metallicRoughness: workflow = .metallicRoughness
        case .specularGlossiness: workflow = .specularGlossiness
        case .unlit: workflow = .unlit
        }
        let alphaMode: MaterialInfo.AlphaMode
        switch material.alphaMode {
        case .opaque: alphaMode = .opaque
        case .mask: alphaMode = .mask
        case .blend: alphaMode = .blend
        }
        return MaterialInfo(
            index: index,
            name: material.name.isEmpty ? "Material" : material.name,
            workflow: workflow,
            alphaMode: alphaMode,
            isDoubleSided: material.isDoubleSided,
            maps: materialMapSet(material.maps),
            metallicFactor: material.metallicFactor.map(Double.init),
            roughnessFactor: material.roughnessFactor.map(Double.init),
            alphaCutoff: material.alphaCutoff.map(Double.init)
        )
    }

    private static func materialMapSet(_ maps: MaterialMapPresence) -> Set<MaterialMap> {
        var result = Set<MaterialMap>()
        if maps.baseColor { result.insert(.baseColor) }
        if maps.normal { result.insert(.normal) }
        if maps.metallicRoughness { result.insert(.metallicRoughness) }
        if maps.occlusion { result.insert(.occlusion) }
        if maps.emissive { result.insert(.emissive) }
        if maps.specular { result.insert(.specular) }
        if maps.clearcoat { result.insert(.clearcoat) }
        if maps.clearcoatRoughness { result.insert(.clearcoatRoughness) }
        if maps.clearcoatNormal { result.insert(.clearcoatNormal) }
        return result
    }
}
