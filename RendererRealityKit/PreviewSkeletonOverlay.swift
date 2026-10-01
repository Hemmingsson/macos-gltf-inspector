import AppKit
import GLTFCore
import RealityKit
import simd

/// Joint spheres + bone segments for skinned models. Markers parent under
/// joint entities so they follow animation; bones update in pivot space.
enum PreviewSkeletonOverlay {
    /// Fit / selection skip-list (`PreviewFloor.isHelperName`).
    static let overlayRootName = "skeletonOverlay"
    static let jointMarkerPrefix = "skeletonJoint"
    static let bonePrefix = "skeletonBone"

    static func isHelperName(_ name: String) -> Bool {
        name == overlayRootName
            || name.hasPrefix(jointMarkerPrefix)
            || name.hasPrefix(bonePrefix)
    }

    /// Attach or remove overlay for `skins` under the model `root` (glTF tree).
    @MainActor
    static func apply(
        show: Bool,
        skins: [GLTFSessionDocument.Skin],
        to root: Entity,
        relativeTo pivot: Entity
    ) {
        clear(from: root, pivot: pivot)
        guard show, !skins.isEmpty else { return }

        let jointRadius = jointRadius(for: root, relativeTo: pivot)
        let thickness = jointRadius * 0.45
        let joints = indexNodes(root)
        let overlay = overlayRoot(in: pivot)
        let sphere = MeshResource.generateSphere(radius: jointRadius)
        let unitBox = MeshResource.generateBox(size: SIMD3<Float>(repeating: 1))
        var jointMaterial = UnlitMaterial(color: NSColor.systemOrange.withAlphaComponent(0.95))
        jointMaterial.faceCulling = .none
        var boneMaterial = UnlitMaterial(color: NSColor.systemTeal.withAlphaComponent(0.85))
        boneMaterial.faceCulling = .none

        var bones: [SkeletonBoneLink] = []
        for (skinIndex, skin) in skins.enumerated() {
            for (jointIndex, nodeIndex) in skin.jointNodeIndices.enumerated() {
                guard let joint = joints[nodeIndex] else { continue }
                joint.addChild(
                    makeJointMarker(
                        skinIndex: skinIndex,
                        jointIndex: jointIndex,
                        mesh: sphere,
                        material: jointMaterial
                    )
                )
            }
            for (jointIndex, parentIndex) in skin.jointParentIndices.enumerated() {
                guard let parentIndex,
                      skin.jointNodeIndices.indices.contains(jointIndex),
                      skin.jointNodeIndices.indices.contains(parentIndex)
                else { continue }
                let childNode = skin.jointNodeIndices[jointIndex]
                let parentNode = skin.jointNodeIndices[parentIndex]
                guard joints[childNode] != nil, joints[parentNode] != nil else { continue }
                let bone = ModelEntity(mesh: unitBox, materials: [boneMaterial])
                bone.name = "\(bonePrefix)-\(skinIndex)-\(jointIndex)"
                overlay.addChild(bone)
                bones.append(SkeletonBoneLink(entity: bone, parentNode: parentNode, childNode: childNode))
            }
        }

        overlay.components.set(
            SkeletonOverlayState(joints: joints, bones: bones, thickness: thickness)
        )
        updateBones(skins: skins, root: root, pivot: pivot, thickness: thickness)
    }

    /// Reposition existing bone segments after animation / auto-rotate.
    @MainActor
    static func updateBones(
        skins: [GLTFSessionDocument.Skin],
        root: Entity,
        pivot: Entity,
        thickness: Float? = nil
    ) {
        guard let overlay = pivot.children.first(where: { $0.name == overlayRootName }),
              let state = overlay.components[SkeletonOverlayState.self]
        else { return }
        let boneThickness = thickness ?? state.thickness
        for bone in state.bones {
            guard let parent = state.joints[bone.parentNode],
                  let child = state.joints[bone.childNode]
            else { continue }
            pose(
                bone.entity,
                from: parent.position(relativeTo: pivot),
                to: child.position(relativeTo: pivot),
                thickness: boneThickness
            )
        }
    }

    @MainActor
    static func clear(from root: Entity, pivot: Entity) {
        func stripMarkers(_ entity: Entity) {
            for child in entity.children.filter({ $0.name.hasPrefix(jointMarkerPrefix) }) {
                child.removeFromParent()
            }
            for child in entity.children {
                stripMarkers(child)
            }
        }
        stripMarkers(root)
        pivot.children.first(where: { $0.name == overlayRootName })?.removeFromParent()
    }

    @MainActor
    private static func overlayRoot(in pivot: Entity) -> Entity {
        if let existing = pivot.children.first(where: { $0.name == overlayRootName }) {
            return existing
        }
        let created = Entity()
        created.name = overlayRootName
        pivot.addChild(created)
        return created
    }

    @MainActor
    private static func makeJointMarker(
        skinIndex: Int,
        jointIndex: Int,
        mesh: MeshResource,
        material: UnlitMaterial
    ) -> ModelEntity {
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = "\(jointMarkerPrefix)-\(skinIndex)-\(jointIndex)"
        return entity
    }

    @MainActor
    private static func pose(
        _ entity: Entity,
        from: SIMD3<Float>,
        to: SIMD3<Float>,
        thickness: Float
    ) {
        let delta = to - from
        let length = max(simd_length(delta), 1e-5)
        entity.position = (from + to) * 0.5
        entity.scale = SIMD3(thickness, thickness, length)
        let direction = delta / length
        // Default box Z aligns with bone; rotate from (0,0,1) to direction.
        let z = SIMD3<Float>(0, 0, 1)
        if abs(simd_dot(z, direction)) < 0.999 {
            entity.orientation = simd_quatf(from: z, to: direction)
        } else if simd_dot(z, direction) < 0 {
            entity.orientation = simd_quatf(angle: .pi, axis: SIMD3(0, 1, 0))
        } else {
            entity.orientation = .init(angle: 0, axis: SIMD3(0, 1, 0))
        }
    }

    @MainActor
    private static func indexNodes(_ root: Entity) -> [Int: Entity] {
        var joints: [Int: Entity] = [:]
        func walk(_ entity: Entity) {
            if let index = entity.components[GLTFNodeIDComponent.self]?.nodeIndex {
                joints[index] = entity
            }
            for child in entity.children {
                walk(child)
            }
        }
        walk(root)
        return joints
    }

    @MainActor
    private static func jointRadius(for root: Entity, relativeTo reference: Entity) -> Float {
        let bounds = PreviewCamera.modelBounds(of: root, relativeTo: reference)
        let extent = bounds.max - bounds.min
        let longest = max(extent.x, max(extent.y, extent.z))
        return min(max(longest * 0.012, 0.004), 0.04)
    }
}

private struct SkeletonBoneLink {
    var entity: Entity
    var parentNode: Int
    var childNode: Int
}

private struct SkeletonOverlayState: Component {
    var joints: [Int: Entity]
    var bones: [SkeletonBoneLink]
    var thickness: Float
}
