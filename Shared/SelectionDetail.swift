import Foundation
import simd

/// Inspector fields for one selected node — only what `GLTFSessionDocument` already stores.
/// Mesh → material indices are not on the document (P14 is file-level materials), so material
/// map chips appear only when `kind == .mesh` and the file lists materials (inventory, not bind).
struct SelectionDetail: Sendable, Equatable {
    struct MaterialChip: Sendable, Equatable {
        var name: String
        var maps: [String]
    }

    struct CameraFields: Sendable, Equatable {
        var type: String
        var yfovDegrees: Float?
        var xmag: Float?
        var ymag: Float?
        var znear: Float
        var zfar: Float?
    }

    struct LightFields: Sendable, Equatable {
        var type: String
        var color: SIMD3<Float>
        var intensity: Float
        var range: Float?
        var innerConeDegrees: Float?
        var outerConeDegrees: Float?
    }

    var name: String
    var kind: GLTFSessionDocument.Node.Kind
    var translation: SIMD3<Float>
    var rotationEulerDegrees: SIMD3<Float>
    var scale: SIMD3<Float>
    var geometryChips: [String]
    var materials: [MaterialChip]
    var camera: CameraFields?
    var light: LightFields?

    var kindLabel: String {
        switch kind {
        case .empty: return "Empty"
        case .mesh: return "Mesh"
        case .camera: return "Camera"
        case .light: return "Light"
        case .skin: return "Skin"
        }
    }

    static func resolve(nodeIndex: Int, in document: GLTFSessionDocument) -> SelectionDetail? {
        guard let node = document.nodes.first(where: { $0.index == nodeIndex }) else { return nil }

        var geometry: [String] = []
        if let meshIndex = node.meshIndex {
            geometry.append("Mesh \(meshIndex)")
        }
        if let skinIndex = node.skinIndex {
            geometry.append("Skin \(skinIndex)")
        }

        let materials: [MaterialChip] =
            node.kind == .mesh
            ? document.materials.map { material in
                MaterialChip(
                    name: material.name.isEmpty ? "Material" : material.name,
                    maps: material.maps.chipLabels
                )
            }
            : []

        return SelectionDetail(
            name: node.name.isEmpty ? "Node \(node.index)" : node.name,
            kind: node.kind,
            translation: node.translation,
            rotationEulerDegrees: eulerDegrees(from: node.rotation),
            scale: node.scale,
            geometryChips: geometry,
            materials: materials,
            camera: cameraFields(for: node, in: document),
            light: lightFields(for: node, in: document)
        )
    }

    private static func cameraFields(
        for node: GLTFSessionDocument.Node,
        in document: GLTFSessionDocument
    ) -> CameraFields? {
        guard node.kind == .camera,
              let index = node.cameraIndex,
              document.cameras.indices.contains(index)
        else { return nil }
        let cam = document.cameras[index]
        return CameraFields(
            type: cam.type,
            yfovDegrees: cam.yfov.map(radiansToDegrees),
            xmag: cam.xmag,
            ymag: cam.ymag,
            znear: cam.znear,
            zfar: cam.zfar
        )
    }

    private static func lightFields(
        for node: GLTFSessionDocument.Node,
        in document: GLTFSessionDocument
    ) -> LightFields? {
        guard node.kind == .light,
              let index = node.lightIndex,
              document.lights.indices.contains(index)
        else { return nil }
        let lamp = document.lights[index]
        return LightFields(
            type: lamp.type,
            color: lamp.color,
            intensity: lamp.intensity,
            range: lamp.range,
            innerConeDegrees: lamp.innerCone.map(radiansToDegrees),
            outerConeDegrees: lamp.outerCone.map(radiansToDegrees)
        )
    }
}

extension MaterialMapPresence {
    /// Short labels for sidebar chips — only maps that are present.
    var chipLabels: [String] {
        var labels: [String] = []
        if baseColor { labels.append("Base Color") }
        if normal { labels.append("Normal") }
        if metallicRoughness { labels.append("Metal-Rough") }
        if occlusion { labels.append("Occlusion") }
        if emissive { labels.append("Emissive") }
        if specular { labels.append("Specular") }
        if clearcoat { labels.append("Clearcoat") }
        if clearcoatRoughness { labels.append("CC Rough") }
        if clearcoatNormal { labels.append("CC Normal") }
        return labels
    }
}

private func radiansToDegrees(_ radians: Float) -> Float {
    radians * 180 / .pi
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

    return SIMD3(
        radiansToDegrees(roll),
        radiansToDegrees(pitch),
        radiansToDegrees(yaw)
    )
}
