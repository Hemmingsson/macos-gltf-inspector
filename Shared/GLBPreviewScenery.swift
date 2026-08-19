import Foundation
import RealityKit

/// One walk of a converted entity for file lights, cameras, and usable clips.
/// Snapshot cameras before `GLBPreviewCamera.makeTurntable` — that removes live
/// camera components so the preview camera is the only view.
enum GLBPreviewScenery {
    enum FileCameraKind: Equatable, Sendable {
        case perspective
        case orthographic
    }

    struct FileCamera {
        let entity: Entity
        let displayName: String
        let kind: FileCameraKind
    }

    /// Point / spot / directional components only — not `DirectionalLightComponent.Shadow()`.
    @MainActor
    static func punctualLightCount(in entity: Entity) -> Int {
        var count = 0
        walk(entity) { node in
            if node.components[PointLightComponent.self] != nil { count += 1 }
            if node.components[SpotLightComponent.self] != nil { count += 1 }
            if node.components[DirectionalLightComponent.self] != nil { count += 1 }
        }
        return count
    }

    /// Live `PerspectiveCameraComponent` or `OrthographicCameraComponent` on each node.
    /// Call while cameras are still live (load time). Display name is the node name, else `Camera N`.
    @MainActor
    static func fileCameras(in entity: Entity) -> [FileCamera] {
        var cameras: [FileCamera] = []
        walk(entity) { node in
            let kind: FileCameraKind?
            if node.components[PerspectiveCameraComponent.self] != nil {
                kind = .perspective
            } else if node.components[OrthographicCameraComponent.self] != nil {
                kind = .orthographic
            } else {
                kind = nil
            }
            guard let kind else { return }
            let trimmed = node.name.trimmingCharacters(in: .whitespacesAndNewlines)
            cameras.append(
                FileCamera(
                    entity: node,
                    displayName: trimmed.isEmpty ? "Camera \(cameras.count + 1)" : trimmed,
                    kind: kind
                )
            )
        }
        return cameras
    }

    /// `Entity.availableAnimations` with `definition.duration > 0`.
    @MainActor
    static func usableAnimations(in entity: Entity) -> [AnimationResource] {
        entity.availableAnimations.filter { animation in
            let duration = animation.definition.duration
            return duration.isFinite && duration > 0
        }
    }

    @MainActor
    private static func walk(_ entity: Entity, _ visit: (Entity) -> Void) {
        visit(entity)
        for child in entity.children {
            walk(child, visit)
        }
    }
}
