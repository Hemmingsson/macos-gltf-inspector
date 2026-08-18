import RealityKit
import simd

enum GLBPreviewCamera {
    private static let fieldOfViewDegrees: Float = 35
    private static let yawDegrees: Float = 35
    private static let pitchDegrees: Float = 18
    static let previewFitPadding: Float = 1.02
    static let thumbnailFitPadding: Float = 1.08
    /// Standing planes (doors, decals): X or Z vs longest. 0.08 catches architectural
    /// doors; snowdrop packs (0.11/1.83 ≈ 0.06) stay below and keep 3/4 framing.
    private static let standingThinRatio: Float = 0.08
    /// Flat ground tiles: Y vs longest.
    private static let groundThinRatio: Float = 0.02

    /// Pivot whose origin is the visual center, so yaw/orbit spin the mesh in place
    /// even when Sketchfab/FBX nodes sit meters away from the scene origin.
    /// Also strips cameras embedded in the glTF so framing uses our turntable camera only.
    @MainActor
    static func makeTurntable(for entity: Entity) -> (pivot: Entity, bounds: BoundingBox) {
        disableFileCameras(entity)
        let worldBounds = modelBounds(of: entity)
        let center = worldBounds.center
        let pivot = Entity()
        pivot.name = "turntable"
        pivot.position = center
        pivot.addChild(entity, preservingWorldTransform: true)
        // Reparenting preserves world transform, so shift by `-center` instead of walking bounds again.
        pivot.position -= center
        let centered = BoundingBox(min: worldBounds.min - center, max: worldBounds.max - center)
        return (pivot, centered)
    }

    /// Union of `ModelComponent` visual bounds. Helper/empty nodes are ignored so
    /// collision boxes do not push the camera out. Falls back to the full entity
    /// if nothing has a mesh yet.
    @MainActor
    static func modelBounds(of entity: Entity) -> BoundingBox {
        var found = false
        var minBound = SIMD3<Float>(repeating: Float.greatestFiniteMagnitude)
        var maxBound = SIMD3<Float>(repeating: -Float.greatestFiniteMagnitude)
        func walk(_ node: Entity) {
            if node.components[ModelComponent.self] != nil {
                let box = node.visualBounds(relativeTo: nil)
                minBound = simd_min(minBound, box.min)
                maxBound = simd_max(maxBound, box.max)
                found = true
            }
            for child in node.children {
                walk(child)
            }
        }
        walk(entity)
        if found, allFinite(minBound), allFinite(maxBound) {
            return BoundingBox(min: minBound, max: maxBound)
        }
        return entity.visualBounds(relativeTo: nil)
    }

    @MainActor
    private static func disableFileCameras(_ entity: Entity) {
        entity.components.remove(PerspectiveCameraComponent.self)
        for child in entity.children {
            disableFileCameras(child)
        }
    }

    /// `nil` = not a decal. 0/1/2 = thin X/Y/Z.
    static func thinAxis(_ extent: SIMD3<Float>) -> Int? {
        let longest = max(extent.x, max(extent.y, extent.z))
        guard longest > 0 else { return nil }
        if extent.x / longest < standingThinRatio { return 0 }
        if extent.y / longest < groundThinRatio { return 1 }
        if extent.z / longest < standingThinRatio { return 2 }
        return nil
    }

    /// Front 3/4, Y-up. glTF models face +Z, so the camera stands on −Z.
    /// Standing decals (thin X or Z) look along the thin axis so the face is visible.
    static func cameraPosition(
        minBound: SIMD3<Float>,
        maxBound: SIMD3<Float>,
        padding: Float,
        aspect: Float = 1
    ) -> SIMD3<Float> {
        let center = (minBound + maxBound) * 0.5
        let extent = maxBound - minBound
        var yaw = yawDegrees * .pi / 180
        let pitch = pitchDegrees * .pi / 180
        if let axis = thinAxis(extent) {
            if axis == 0 { yaw = .pi / 2 }
            if axis == 2 { yaw = 0 }
        }
        // Unit vector from the model center toward the camera.
        let toCamera = SIMD3<Float>(
            sin(yaw) * cos(pitch),
            sin(pitch),
            -cos(yaw) * cos(pitch)
        )
        let distance = fitDistance(extent: extent, toCamera: toCamera, aspect: aspect, padding: padding)
        return center + distance * toCamera
    }

    /// Distance that frames the model's *projected bounding box* — not its bounding
    /// sphere — so irregular shapes (a tree, a car) fill the viewport instead of
    /// floating inside the sphere's slack. Fits both the horizontal and vertical FOV.
    private static func fitDistance(
        extent: SIMD3<Float>,
        toCamera: SIMD3<Float>,
        aspect: Float,
        padding: Float
    ) -> Float {
        let forward = -toCamera
        var right = cross(forward, SIMD3<Float>(0, 1, 0))
        // forward parallel to world up (top-down decals): pick any horizontal axis.
        right = length(right) < 1e-4 ? SIMD3<Float>(1, 0, 0) : normalize(right)
        let up = normalize(cross(right, forward))
        // Half-extent of an axis-aligned box projected onto a unit axis (closed form).
        let half = extent * 0.5
        func projectedHalf(_ axis: SIMD3<Float>) -> Float {
            abs(axis.x) * half.x + abs(axis.y) * half.y + abs(axis.z) * half.z
        }
        // RealityView.make often runs before layout; a ~0 aspect used to push the
        // camera tens of kilometers away so the first frames looked empty.
        let safeAspect = (aspect > 0.05 && aspect < 20) ? aspect : 1
        let vHalfFOV = fieldOfViewDegrees * .pi / 360 // camera FOV orientation is vertical
        let hHalfFOV = atan(tan(vHalfFOV) * safeAspect)
        let distanceV = projectedHalf(up) / tan(vHalfFOV)
        let distanceH = projectedHalf(right) / tan(hHalfFOV)
        // + depth so the near face of the box still fits, not just the center slice.
        let distance = max(distanceV, distanceH) + projectedHalf(forward)
        return max(0.0001, distance * padding)
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
        return camera
    }

    private static func allFinite(_ v: SIMD3<Float>) -> Bool {
        v.x.isFinite && v.y.isFinite && v.z.isFinite
    }
}
