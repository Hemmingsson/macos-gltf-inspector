import AppKit
import GLTFCore
import RealityKit
import simd

public enum PreviewCamera {
    /// Default front-three-quarter yaw (degrees). Iso preset uses the same value.
    static let yawDegrees: Float = 35
    /// Default front-three-quarter pitch (degrees). Iso preset uses the same value.
    static let pitchDegrees: Float = 18
    static let previewFitPadding: Float = 1.02
    static let thumbnailFitPadding: Float = 1.08
    static let autoRotateSpinName = "autoRotateSpin"
    /// RGB axis triad at the authored glTF origin when Center is off.
    static let worldOriginGizmoName = "worldOriginGizmo"
    private static let axisGizmoLength: Float = 0.2
    private static let axisGizmoThickness: Float = 0.008

    /// Pivot origin = visual center when `center` is true. Spin child holds the
    /// model so auto-rotate does not yaw `cameraTarget`. File cameras stay on
    /// nodes; live camera components are stripped so the preview camera is the
    /// only active view.
    ///
    /// When `center` is false, the authored offset is kept and a world-origin
    /// axis gizmo is parented under the pivot at the entity's local origin
    /// (glTF (0,0,0) in pivot space).
    @MainActor
    static func makeTurntable(
        for entity: Entity,
        center: Bool = true
    ) -> (pivot: Entity, spin: Entity, bounds: BoundingBox) {
        disableCameras(in: entity)
        // Unattached trees treat each mesh origin as world — measure in root
        // space, then pull that center to the pivot when centering.
        let localBounds = modelBounds(of: entity, relativeTo: entity)
        let meshCenter = localBounds.center
        let pivot = Entity()
        pivot.name = "turntable"
        let spin = Entity()
        spin.name = autoRotateSpinName
        pivot.addChild(spin)
        spin.addChild(entity)
        let centerInPivot = entity.convert(position: meshCenter, to: pivot)
        let framed: BoundingBox
        if center {
            entity.position -= centerInPivot
            framed = BoundingBox(min: localBounds.min - meshCenter, max: localBounds.max - meshCenter)
        } else {
            // Authored origin = entity local 0 in pivot space (not `-centerInPivot`,
            // which is only where that origin lands *after* centering).
            let authoredOrigin = entity.convert(position: .zero, to: pivot)
            pivot.addChild(makeAxisGizmo(at: authoredOrigin))
            framed = modelBounds(of: entity, relativeTo: pivot)
        }
        return (pivot, spin, framed)
    }

    /// Small RGB axis triad (X red, Y green, Z blue) at `position` in parent space.
    @MainActor
    static func makeAxisGizmo(at position: SIMD3<Float>, length: Float = axisGizmoLength) -> Entity {
        let root = Entity()
        root.name = worldOriginGizmoName
        root.position = position
        let half = length * 0.5
        let t = axisGizmoThickness
        root.addChild(axisArm(size: SIMD3(length, t, t), mid: SIMD3(half, 0, 0), color: .red))
        root.addChild(axisArm(size: SIMD3(t, length, t), mid: SIMD3(0, half, 0), color: .green))
        root.addChild(axisArm(size: SIMD3(t, t, length), mid: SIMD3(0, 0, half), color: .blue))
        return root
    }

    @MainActor
    private static func axisArm(size: SIMD3<Float>, mid: SIMD3<Float>, color: NSColor) -> ModelEntity {
        var material = UnlitMaterial(color: color)
        material.faceCulling = .none
        let entity = ModelEntity(
            mesh: .generateBox(size: size),
            materials: [material]
        )
        entity.position = mid
        return entity
    }

    /// Pose the live preview camera to a front-three-quarter fit of `bounds`.
    /// When `orthographic` is true, swaps to `OrthographicCameraComponent` and sets
    /// `scale` so the projected bounds fill the viewport.
    ///
    /// Pass `preset:` (or explicit `yaw`/`pitch` with `applyThinAxisOverride: false`) for
    /// view presets — thin-axis override stays on for the default Fit path only.
    @MainActor
    static func applyFit(
        to camera: Entity,
        bounds: BoundingBox,
        padding: Float = previewFitPadding,
        aspect: Float = 1,
        orbitFocus: Entity? = nil,
        orthographic: Bool = false,
        yaw: Float = yawDegrees,
        pitch: Float = pitchDegrees,
        applyThinAxisOverride: Bool = true,
        fieldOfViewInDegrees: Float = RenderCamera.defaultFieldOfViewDegrees
    ) {
        guard !bounds.isEmpty else { return }
        let center = (bounds.min + bounds.max) * 0.5
        // Pivot stays at the visual center (usually world origin after turntable).
        orbitFocus?.setPosition(.zero, relativeTo: nil)
        let fov = RenderCamera.clampedFieldOfView(fieldOfViewInDegrees)
        let eye = cameraPosition(
            minBound: bounds.min,
            maxBound: bounds.max,
            padding: padding,
            aspect: aspect,
            yaw: yaw,
            pitch: pitch,
            applyThinAxisOverride: applyThinAxisOverride,
            fieldOfViewInDegrees: fov
        )
        applyView(to: camera, eye: eye, target: center)
        if orthographic {
            applyOrthographicProjection(
                to: camera,
                bounds: bounds,
                aspect: aspect,
                padding: padding,
                eye: eye,
                target: center
            )
        } else {
            restoreFitPerspective(on: camera, fieldOfViewInDegrees: fov)
            if var perspective = camera.components[PerspectiveCameraComponent.self] {
                applyFitClip(to: &perspective, eye: eye, target: center)
                camera.components.set(perspective)
            }
        }
    }

    /// Reframe with a named preset. Thin-axis override is always off.
    @MainActor
    static func applyFit(
        to camera: Entity,
        bounds: BoundingBox,
        padding: Float = previewFitPadding,
        aspect: Float = 1,
        orbitFocus: Entity? = nil,
        orthographic: Bool = false,
        preset: CameraPreset,
        fieldOfViewInDegrees: Float = RenderCamera.defaultFieldOfViewDegrees
    ) {
        applyFit(
            to: camera,
            bounds: bounds,
            padding: padding,
            aspect: aspect,
            orbitFocus: orbitFocus,
            orthographic: orthographic,
            yaw: preset.yawDegrees,
            pitch: preset.pitchDegrees,
            applyThinAxisOverride: false,
            fieldOfViewInDegrees: fieldOfViewInDegrees
        )
    }

    /// Update live perspective FOV without moving the camera. No-op while ortho.
    @MainActor
    static func applyFieldOfView(to camera: Entity, degrees: Float) {
        guard camera.components[OrthographicCameraComponent.self] == nil else { return }
        guard var perspective = camera.components[PerspectiveCameraComponent.self] else { return }
        perspective.fieldOfViewInDegrees = RenderCamera.clampedFieldOfView(degrees)
        camera.components.set(perspective)
    }

    /// Keep pose; swap to ortho and set `scale` / near / far from bounds + look.
    @MainActor
    static func applyOrthographicProjection(
        to camera: Entity,
        bounds: BoundingBox,
        aspect: Float = 1,
        padding: Float = previewFitPadding,
        eye: SIMD3<Float>? = nil,
        target: SIMD3<Float>? = nil
    ) {
        guard !bounds.isEmpty else { return }
        let resolvedEye = eye ?? camera.position(relativeTo: nil)
        let resolvedTarget = target ?? bounds.center
        camera.components.remove(PerspectiveCameraComponent.self)
        var orthographic = OrthographicCameraComponent()
        orthographic.scale = orthographicScale(
            bounds: bounds,
            eye: resolvedEye,
            target: resolvedTarget,
            aspect: aspect,
            padding: padding
        )
        orthographic.scaleDirection = .vertical
        applyFitClip(to: &orthographic, eye: resolvedEye, target: resolvedTarget)
        camera.components.set(orthographic)
    }

    /// Recompute ortho `scale` only (viewport resize). Pose unchanged.
    @MainActor
    static func updateOrthographicScale(
        on camera: Entity,
        bounds: BoundingBox,
        aspect: Float = 1,
        padding: Float = previewFitPadding
    ) {
        guard var orthographic = camera.components[OrthographicCameraComponent.self],
              !bounds.isEmpty
        else { return }
        let eye = camera.position(relativeTo: nil)
        let target = bounds.center
        orthographic.scale = orthographicScale(
            bounds: bounds,
            eye: eye,
            target: target,
            aspect: aspect,
            padding: padding
        )
        applyFitClip(to: &orthographic, eye: eye, target: target)
        camera.components.set(orthographic)
    }

    /// Union of `ModelComponent` visual bounds. Helper/empty nodes are ignored so
    /// collision boxes do not push the camera out. Falls back to the full entity
    /// if nothing has a mesh yet.
    ///
    /// For a W×H×D meters readout see `LoadedModel.extent` / `ModelDimensions`.
    @MainActor
    static func modelBounds(of entity: Entity, relativeTo reference: Entity? = nil) -> BoundingBox {
        var boxes: [BoundingBox] = []
        func walk(_ node: Entity) {
            // Floor / selection / origin-gizmo / skeleton helpers carry ModelComponents;
            // skip their subtrees so Fit framing stays on the glTF mesh only.
            if PreviewFloor.isHelperName(node.name) {
                return
            }
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

    @MainActor
    static func makeFrontThreeQuarter(
        minBound: SIMD3<Float>,
        maxBound: SIMD3<Float>,
        padding: Float,
        aspect: Float = 1,
        yaw: Float = yawDegrees,
        pitch: Float = pitchDegrees,
        applyThinAxisOverride: Bool = true,
        fieldOfViewInDegrees: Float = RenderCamera.defaultFieldOfViewDegrees
    ) -> PerspectiveCamera {
        let center = (minBound + maxBound) * 0.5
        let fov = RenderCamera.clampedFieldOfView(fieldOfViewInDegrees)
        let position = cameraPosition(
            minBound: minBound,
            maxBound: maxBound,
            padding: padding,
            aspect: aspect,
            yaw: yaw,
            pitch: pitch,
            applyThinAxisOverride: applyThinAxisOverride,
            fieldOfViewInDegrees: fov
        )
        let camera = PerspectiveCamera()
        camera.name = "previewCamera"
        camera.camera.fieldOfViewInDegrees = fov
        camera.camera.fieldOfViewOrientation = .vertical
        // Avoid `Entity.look(at:from:)` — traps when the view axis ‖ world +Y.
        applyView(to: camera, eye: position, target: center)
        applyFitClip(to: &camera.camera, eye: position, target: center)
        return camera
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
    static func restoreFitPerspective(
        on preview: Entity,
        fieldOfViewInDegrees: Float = RenderCamera.defaultFieldOfViewDegrees
    ) {
        preview.components.remove(OrthographicCameraComponent.self)
        var camera = preview.components[PerspectiveCameraComponent.self] ?? PerspectiveCameraComponent()
        camera.fieldOfViewInDegrees = RenderCamera.clampedFieldOfView(fieldOfViewInDegrees)
        camera.fieldOfViewOrientation = .vertical
        preview.components.set(camera)
    }

    private static func allFinite(_ v: SIMD3<Float>) -> Bool {
        v.x.isFinite && v.y.isFinite && v.z.isFinite
    }

    /// Pose `camera` at `eye` looking at `target` with a stable Y-up basis.
    /// Interactive orbit uses RealityKit `CameraControls.orbit` — not this helper.
    @MainActor
    static func applyView(to camera: Entity, eye: SIMD3<Float>, target: SIMD3<Float>) {
        let offset = eye - target
        let radius = length(offset)
        guard radius > 1e-4,
              eye.x.isFinite, eye.y.isFinite, eye.z.isFinite,
              target.x.isFinite, target.y.isFinite, target.z.isFinite
        else { return }

        let polar = acos(min(max(offset.y / radius, -1), 1))
        let yaw = atan2(offset.x, offset.z)
        let sinP = sin(polar)
        let cosP = cos(polar)
        let sinY = sin(yaw)
        let cosY = cos(yaw)
        let look = SIMD3<Float>(-sinP * sinY, -cosP, -sinP * cosY)
        let right = SIMD3<Float>(cosY, 0, -sinY)
        var up = cross(right, look)
        let upLength = length(up)
        if upLength > 1e-5 {
            up /= upLength
        } else {
            up = SIMD3(0, 0, 1)
        }
        camera.setPosition(eye, relativeTo: nil)
        camera.orientation = simd_quatf(simd_float3x3(columns: (right, up, -look)))
    }
}
