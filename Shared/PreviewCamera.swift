import RealityKit
import simd

enum PreviewCamera {
    static let defaultFieldOfViewDegrees: Float = 35
    private static let fieldOfViewDegrees: Float = defaultFieldOfViewDegrees
    private static let yawDegrees: Float = 35
    private static let pitchDegrees: Float = 18
    static let previewFitPadding: Float = 1.02
    static let thumbnailFitPadding: Float = 1.08
    /// Standing planes (doors, decals): X or Z vs longest. 0.08 catches architectural
    /// doors; snowdrop packs (0.11/1.83 ≈ 0.06) stay below and keep 3/4 framing.
    private static let standingThinRatio: Float = 0.08
    /// Flat ground tiles: Y vs longest.
    private static let groundThinRatio: Float = 0.02

    static let autoRotateSpinName = "autoRotateSpin"

    /// Pivot origin = visual center. Spin child holds the model so auto-rotate
    /// does not yaw `cameraTarget`. File cameras stay on nodes; live camera
    /// components are stripped so the preview camera is the only active view.
    @MainActor
    static func makeTurntable(for entity: Entity) -> (pivot: Entity, spin: Entity, bounds: BoundingBox) {
        disableCameras(in: entity)
        // Unattached trees treat each mesh origin as world — measure in root
        // space, then pull that center to the pivot.
        let localBounds = modelBounds(of: entity, relativeTo: entity)
        let center = localBounds.center
        let pivot = Entity()
        pivot.name = "turntable"
        let spin = Entity()
        spin.name = autoRotateSpinName
        pivot.addChild(spin)
        spin.addChild(entity)
        let centerInPivot = entity.convert(position: center, to: pivot)
        entity.position -= centerInPivot
        let centered = BoundingBox(min: localBounds.min - center, max: localBounds.max - center)
        return (pivot, spin, centered)
    }

    /// Pose the live preview camera to a front-three-quarter fit of `bounds`.
    @MainActor
    static func applyFit(
        to camera: Entity,
        bounds: BoundingBox,
        padding: Float = previewFitPadding,
        aspect: Float = 1,
        orbitFocus: Entity? = nil
    ) {
        guard !bounds.isEmpty else { return }
        let center = (bounds.min + bounds.max) * 0.5
        // Pivot stays at the visual center (usually world origin after turntable).
        orbitFocus?.setPosition(.zero, relativeTo: nil)
        let fitted = makeFrontThreeQuarter(
            minBound: bounds.min,
            maxBound: bounds.max,
            padding: padding,
            aspect: aspect
        )
        let eye = fitted.position(relativeTo: nil)
        PreviewOrbit.applyView(to: camera, eye: eye, target: center)
        if var perspective = camera.components[PerspectiveCameraComponent.self] {
            applyFitClip(to: &perspective, eye: eye, target: center)
            camera.components.set(perspective)
        }
    }

    /// A leftover mesh this many times larger than the median mesh is ignored
    /// for Fit. Typical case: Blender cm-scale helper beside a `0.01` asset.
    /// Equal-sized city tiles stay; they share one scale.
    static let outlierExtentRatio: Float = 32

    /// Union of `ModelComponent` visual bounds. Helper/empty nodes are ignored so
    /// collision boxes do not push the camera out. Falls back to the full entity
    /// if nothing has a mesh yet.
    @MainActor
    static func modelBounds(of entity: Entity, relativeTo reference: Entity? = nil) -> BoundingBox {
        var boxes: [BoundingBox] = []
        func walk(_ node: Entity) {
            // Floor / selection helpers carry ModelComponents; skip their subtrees
            // so Fit framing stays on the glTF mesh only.
            if PreviewFloor.isHelperName(node.name) { return }
            if node.components[ModelComponent.self] != nil {
                let box = node.visualBounds(recursive: false, relativeTo: reference)
                if !box.isEmpty, allFinite(box.min), allFinite(box.max) {
                    boxes.append(box)
                }
            }
            for child in node.children {
                walk(child)
            }
        }
        walk(entity)
        if let union = unionModelBoxes(boxes) {
            return union
        }
        return entity.visualBounds(relativeTo: reference)
    }

    /// Keep the cluster of typical mesh sizes; drop a single km-scale leftover.
    static func unionModelBoxes(_ boxes: [BoundingBox]) -> BoundingBox? {
        let finite = boxes.filter { !$0.isEmpty && allFinite($0.min) && allFinite($0.max) }
        guard !finite.isEmpty else { return nil }
        let extents = finite.map { longest($0.max - $0.min) }
        let kept: [BoundingBox]
        if finite.count >= 3 {
            let mid = median(extents)
            if mid > 0 {
                let limit = mid * outlierExtentRatio
                let filtered = zip(finite, extents).compactMap { box, ext in
                    ext <= limit ? box : nil
                }
                kept = filtered.isEmpty ? finite : filtered
            } else {
                kept = finite
            }
        } else {
            kept = finite
        }
        var minBound = SIMD3<Float>(repeating: Float.greatestFiniteMagnitude)
        var maxBound = SIMD3<Float>(repeating: -Float.greatestFiniteMagnitude)
        for box in kept {
            minBound = simd_min(minBound, box.min)
            maxBound = simd_max(maxBound, box.max)
        }
        return BoundingBox(min: minBound, max: maxBound)
    }

    static func longest(_ extent: SIMD3<Float>) -> Float {
        max(extent.x, max(extent.y, extent.z))
    }

    static func median(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) * 0.5
        }
        return sorted[mid]
    }

    /// Removes live camera components so RealityKit uses the preview camera.
    /// Mesh-bearing camera nodes stay visible and keep their transforms.
    @MainActor
    private static func disableCameras(in root: Entity) {
        func walk(_ entity: Entity) {
            entity.components.remove(PerspectiveCameraComponent.self)
            entity.components.remove(OrthographicCameraComponent.self)
            for child in entity.children {
                walk(child)
            }
        }
        walk(root)
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

    /// Standing planes (thin X or Z): Fit orbit would spin the face away.
    static func disablesAutoRotate(_ extent: SIMD3<Float>) -> Bool {
        guard let axis = thinAxis(extent) else { return false }
        return axis == 0 || axis == 2
    }

    /// Front 3/4, Y-up. glTF +Z is forward, so the camera stands on +Z.
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
            cos(yaw) * cos(pitch)
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
        // Avoid `Entity.look(at:from:)` — traps when the view axis ‖ world +Y.
        PreviewOrbit.applyView(to: camera, eye: position, target: center)
        applyFitClip(to: &camera.camera, eye: position, target: center)
        return camera
    }

    /// Default RealityKit far/near clips a 3 km tile or a 12 cm ashtray.
    static func applyFitClip(to camera: inout PerspectiveCameraComponent, eye: SIMD3<Float>, target: SIMD3<Float>) {
        let distance = max(length(eye - target), 0.001)
        camera.near = max(0.0005, distance * 0.0008)
        camera.far = max(200, distance * 40)
    }

    /// World pose from the glTF camera node plus projection from the session document.
    @MainActor
    static func applyFileView(
        to preview: Entity,
        cameraNode: Entity,
        spec: GLTFSessionDocument.Camera
    ) {
        preview.setPosition(cameraNode.position(relativeTo: nil), relativeTo: nil)
        preview.orientation = cameraNode.orientation(relativeTo: nil)
        if spec.type == "orthographic" {
            preview.components.remove(PerspectiveCameraComponent.self)
            var orthographic = OrthographicCameraComponent()
            orthographic.near = spec.znear
            if let far = spec.zfar, far.isFinite, far > spec.znear {
                orthographic.far = far
            }
            orthographic.scale = spec.ymag ?? spec.xmag ?? 1
            preview.components.set(orthographic)
            return
        }
        preview.components.remove(OrthographicCameraComponent.self)
        var perspective = preview.components[PerspectiveCameraComponent.self] ?? PerspectiveCameraComponent()
        if let yfov = spec.yfov, yfov > 0 {
            perspective.fieldOfViewInDegrees = yfov * 180 / .pi
        }
        perspective.fieldOfViewOrientation = .vertical
        perspective.near = spec.znear
        if let far = spec.zfar, far.isFinite, far > spec.znear {
            perspective.far = far
        }
        preview.components.set(perspective)
    }

    @MainActor
    static func restoreFitPerspective(on preview: Entity) {
        preview.components.remove(OrthographicCameraComponent.self)
        var camera = preview.components[PerspectiveCameraComponent.self] ?? PerspectiveCameraComponent()
        camera.fieldOfViewInDegrees = fieldOfViewDegrees
        camera.fieldOfViewOrientation = .vertical
        preview.components.set(camera)
    }

    private static func allFinite(_ v: SIMD3<Float>) -> Bool {
        v.x.isFinite && v.y.isFinite && v.z.isFinite
    }
}
