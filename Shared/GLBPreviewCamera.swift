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
    /// File cameras stay on their nodes; live camera components are stored and
    /// removed so the preview camera is the only active view.
    @MainActor
    static func makeTurntable(for entity: Entity) -> (pivot: Entity, bounds: BoundingBox) {
        disableCameras(in: entity)
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

    /// Stores and removes `PerspectiveCameraComponent` / `OrthographicCameraComponent`
    /// on `root` and descendants. Does not set `entity.isEnabled` (a mesh-bearing
    /// camera node must stay visible) and does not reparent.
    @MainActor
    static func disableCameras(in root: Entity) {
        StoredCameraComponent.registerIfNeeded()
        walk(root) { disableCameraComponents(on: $0) }
    }

    /// Reattaches every stored camera component under `root`. Does not enforce a
    /// single active camera — use `activateCamera` for that.
    @MainActor
    static func restoreCameras(in root: Entity) {
        StoredCameraComponent.registerIfNeeded()
        walk(root) { restoreCamera(on: $0) }
    }

    /// Reattaches a stored perspective or orthographic camera on one entity.
    @MainActor
    static func restoreCamera(on entity: Entity) {
        StoredCameraComponent.registerIfNeeded()
        guard let store = entity.components[StoredCameraComponent.self] else { return }
        if let perspective = store.perspective {
            entity.components.set(perspective)
        }
        if let orthographic = store.orthographic {
            entity.components.set(orthographic)
        }
    }

    /// Disables every camera under `roots` (and `camera` if it is outside them),
    /// then restores only `camera`. glTF ignores node scale on the view matrix,
    /// so the active camera is given unit world scale.
    @MainActor
    static func activateCamera(_ camera: Entity, disablingOthersIn roots: [Entity]) {
        StoredCameraComponent.registerIfNeeded()
        var seen = Set<ObjectIdentifier>()
        func disableTree(_ root: Entity) {
            let id = ObjectIdentifier(root)
            guard seen.insert(id).inserted else { return }
            disableCameras(in: root)
        }
        for root in roots {
            disableTree(root)
        }
        disableTree(camera)
        restoreCamera(on: camera)
        applyUnscaledCameraView(camera)
    }

    @MainActor
    private static func disableCameraComponents(on entity: Entity) {
        var store = entity.components[StoredCameraComponent.self] ?? StoredCameraComponent()
        var changed = false
        if let perspective = entity.components[PerspectiveCameraComponent.self] {
            store.perspective = perspective
            entity.components.remove(PerspectiveCameraComponent.self)
            changed = true
        }
        if let orthographic = entity.components[OrthographicCameraComponent.self] {
            store.orthographic = orthographic
            entity.components.remove(OrthographicCameraComponent.self)
            changed = true
        }
        guard store.perspective != nil || store.orthographic != nil else { return }
        if store.localScale == nil {
            store.localScale = entity.scale
        } else {
            entity.scale = store.localScale!
        }
        if changed || entity.components[StoredCameraComponent.self] == nil {
            entity.components.set(store)
        }
    }

    /// glTF cameras look −Z / +Y up and must not inherit node scale.
    @MainActor
    private static func applyUnscaledCameraView(_ entity: Entity) {
        entity.setScale(.one, relativeTo: nil)
    }

    @MainActor
    private static func walk(_ entity: Entity, _ visit: (Entity) -> Void) {
        visit(entity)
        for child in entity.children {
            walk(child, visit)
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

/// Holds camera components removed so a node can keep its mesh and clip path.
private struct StoredCameraComponent: Component, Equatable {
    var perspective: PerspectiveCameraComponent?
    var orthographic: OrthographicCameraComponent?
    var localScale: SIMD3<Float>?

    static func registerIfNeeded() {
        _ = registration
    }

    private static let registration: Void = {
        StoredCameraComponent.registerComponent()
    }()
}
