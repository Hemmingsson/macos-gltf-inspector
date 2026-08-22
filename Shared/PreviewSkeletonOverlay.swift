import AppKit
import RealityKit
import simd

/// Joint spheres + bone segments for skinned models. Markers parent under
/// joint entities so they follow animation; bones update in pivot space.
enum PreviewSkeletonOverlay {
    /// Fit / selection skip-list (also inlined in `PreviewCamera.modelBounds`).
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
        for (skinIndex, skin) in skins.enumerated() {
            for (jointIndex, nodeIndex) in skin.jointNodeIndices.enumerated() {
                guard let joint = GLTFNodeLookup.entity(nodeIndex: nodeIndex, in: root) else {
                    continue
                }
                joint.addChild(makeJointMarker(skinIndex: skinIndex, jointIndex: jointIndex, radius: jointRadius))
            }
        }
        updateBones(skins: skins, root: root, pivot: pivot, thickness: jointRadius * 0.45)
    }

    /// Reposition bone segments after animation / auto-rotate (call from RealityView update).
    @MainActor
    static func updateBones(
        skins: [GLTFSessionDocument.Skin],
        root: Entity,
        pivot: Entity,
        thickness: Float? = nil
    ) {
        let overlay = overlayRoot(in: pivot)
        for child in overlay.children where child.name.hasPrefix(bonePrefix) {
            child.removeFromParent()
        }

        let boneThickness = thickness ?? jointRadius(for: root, relativeTo: pivot) * 0.45
        var material = UnlitMaterial(color: NSColor.systemTeal.withAlphaComponent(0.85))
        material.faceCulling = .none

        for (skinIndex, skin) in skins.enumerated() {
            for (jointIndex, parentIndex) in skin.jointParentIndices.enumerated() {
                guard let parentIndex,
                      skin.jointNodeIndices.indices.contains(jointIndex),
                      skin.jointNodeIndices.indices.contains(parentIndex)
                else { continue }
                let childNode = skin.jointNodeIndices[jointIndex]
                let parentNode = skin.jointNodeIndices[parentIndex]
                guard let child = GLTFNodeLookup.entity(nodeIndex: childNode, in: root),
                      let parent = GLTFNodeLookup.entity(nodeIndex: parentNode, in: root)
                else { continue }
                let a = parent.position(relativeTo: pivot)
                let b = child.position(relativeTo: pivot)
                overlay.addChild(
                    makeBone(
                        from: a,
                        to: b,
                        thickness: boneThickness,
                        material: material,
                        name: "\(bonePrefix)-\(skinIndex)-\(jointIndex)"
                    )
                )
            }
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
    private static func makeJointMarker(skinIndex: Int, jointIndex: Int, radius: Float) -> ModelEntity {
        var material = UnlitMaterial(color: NSColor.systemOrange.withAlphaComponent(0.95))
        material.faceCulling = .none
        let entity = ModelEntity(
            mesh: .generateSphere(radius: radius),
            materials: [material]
        )
        entity.name = "\(jointMarkerPrefix)-\(skinIndex)-\(jointIndex)"
        return entity
    }

    @MainActor
    private static func makeBone(
        from: SIMD3<Float>,
        to: SIMD3<Float>,
        thickness: Float,
        material: UnlitMaterial,
        name: String
    ) -> ModelEntity {
        let delta = to - from
        let length = max(simd_length(delta), 1e-5)
        let entity = ModelEntity(
            mesh: .generateBox(size: SIMD3(thickness, thickness, length)),
            materials: [material]
        )
        entity.name = name
        entity.position = (from + to) * 0.5
        let direction = delta / length
        // Default box Z aligns with bone; rotate from (0,0,1) to direction.
        let z = SIMD3<Float>(0, 0, 1)
        if abs(simd_dot(z, direction)) < 0.999 {
            entity.orientation = simd_quatf(from: z, to: direction)
        } else if simd_dot(z, direction) < 0 {
            entity.orientation = simd_quatf(angle: .pi, axis: SIMD3(0, 1, 0))
        }
        return entity
    }

    @MainActor
    private static func jointRadius(for root: Entity, relativeTo reference: Entity) -> Float {
        let bounds = PreviewCamera.modelBounds(of: root, relativeTo: reference)
        let extent = bounds.max - bounds.min
        let longest = max(extent.x, max(extent.y, extent.z))
        return min(max(longest * 0.012, 0.004), 0.04)
    }
}
