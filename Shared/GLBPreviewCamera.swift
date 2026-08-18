import RealityKit
import simd

enum GLBPreviewCamera {
    private static let fieldOfViewDegrees: Float = 35
    private static let yawDegrees: Float = 35
    private static let pitchDegrees: Float = 18
    static let previewFitPadding: Float = 1.15
    static let thumbnailFitPadding: Float = 1.08

    /// Pivot whose origin is the visual center, so yaw/orbit spin the mesh in place
    /// even when Sketchfab/FBX nodes sit meters away from the scene origin.
    /// Also strips cameras embedded in the glTF so framing uses our turntable camera only.
    @MainActor
    static func makeTurntable(for entity: Entity) -> (pivot: Entity, bounds: BoundingBox) {
        GLBLog.event(GLBLog.camera, "makeTurntable in \(GLBLog.describe(entity))")
        disableFileCameras(entity)
        let worldBounds = entity.visualBounds(relativeTo: nil)
        let center = worldBounds.center
        GLBLog.event(
            GLBLog.camera,
            "worldBounds min=\(GLBLog.fmt3(worldBounds.min)) max=\(GLBLog.fmt3(worldBounds.max)) center=\(GLBLog.fmt3(center)) extent=\(GLBLog.fmt3(worldBounds.max - worldBounds.min))"
        )
        let pivot = Entity()
        pivot.name = "turntable"
        pivot.position = center
        pivot.addChild(entity, preservingWorldTransform: true)
        // After reparenting with world transform preserved, pivot bounds match
        // `worldBounds`. Shifting the pivot by `-center` recenters without another walk.
        pivot.position -= center
        let centered = BoundingBox(min: worldBounds.min - center, max: worldBounds.max - center)
        GLBLog.event(
            GLBLog.camera,
            "turntable recentered min=\(GLBLog.fmt3(centered.min)) max=\(GLBLog.fmt3(centered.max)) pivot.pos=\(GLBLog.fmt3(pivot.position))"
        )
        return (pivot, centered)
    }

    @MainActor
    private static func disableFileCameras(_ entity: Entity) {
        let hadCamera = entity.components[PerspectiveCameraComponent.self] != nil
        entity.components.remove(PerspectiveCameraComponent.self)
        if hadCamera {
            GLBLog.event(GLBLog.camera, "disabled file camera on \(entity.name.isEmpty ? "(unnamed)" : entity.name)")
        }
        for child in entity.children {
            disableFileCameras(child)
        }
    }

    /// Front 3/4, Y-up. glTF models face +Z, so the camera stands on −Z.
    static func cameraPosition(
        minBound: SIMD3<Float>,
        maxBound: SIMD3<Float>,
        padding: Float,
        aspect: Float = 1
    ) -> SIMD3<Float> {
        let center = (minBound + maxBound) * 0.5
        let extent = maxBound - minBound
        let radius = max(0.0001, length(extent) * 0.5)
        let distance = fitDistance(radius: radius, aspect: aspect, padding: padding)
        let yaw = yawDegrees * .pi / 180
        let pitch = pitchDegrees * .pi / 180
        let position = SIMD3<Float>(
            center.x + distance * sin(yaw) * cos(pitch),
            center.y + distance * sin(pitch),
            center.z - distance * cos(yaw) * cos(pitch)
        )
        return position
    }

    /// Distance that keeps a bounding sphere inside the view even if FOV is applied
    /// to the long axis of a non-square viewport.
    private static func fitDistance(radius: Float, aspect: Float, padding: Float) -> Float {
        let fovHalf = fieldOfViewDegrees * .pi / 360
        let safeAspect = max(aspect, 0.0001)
        let longOverShort = max(safeAspect, 1 / safeAspect)
        let limitingHalf = atan(tan(fovHalf) / longOverShort)
        return (radius / tan(limitingHalf)) * padding
    }

    @MainActor
    static func makeFrontThreeQuarter(
        minBound: SIMD3<Float>,
        maxBound: SIMD3<Float>,
        padding: Float,
        aspect: Float = 1
    ) -> PerspectiveCamera {
        let center = (minBound + maxBound) * 0.5
        let position = cameraPosition(minBound: minBound, maxBound: maxBound, padding: padding, aspect: aspect)
        let camera = PerspectiveCamera()
        camera.name = "previewCamera"
        camera.camera.fieldOfViewInDegrees = fieldOfViewDegrees
        camera.camera.fieldOfViewOrientation = .vertical
        camera.look(at: center, from: position, relativeTo: nil)
        GLBLog.event(
            GLBLog.camera,
            "makeFrontThreeQuarter fov=\(fieldOfViewDegrees) aspect=\(aspect) padding=\(padding) from=\(GLBLog.fmt3(position)) at=\(GLBLog.fmt3(center))"
        )
        return camera
    }
}
