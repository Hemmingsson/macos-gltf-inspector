import AppKit
import RealityKit
import simd

enum PreviewCamera {
    static let defaultFieldOfViewDegrees: Float = 35
    /// Session FOV slider range (degrees). Fit distance uses the live value.
    static let fieldOfViewRange: ClosedRange<Float> = 15...90
    /// Default front-three-quarter yaw (degrees). Iso preset uses the same value.
    static let yawDegrees: Float = 35
    /// Default front-three-quarter pitch (degrees). Iso preset uses the same value.
    static let pitchDegrees: Float = 18
    static let previewFitPadding: Float = 1.02
    static let thumbnailFitPadding: Float = 1.08
    /// Standing planes (doors, decals): X or Z vs longest. 0.08 catches architectural
    /// doors; snowdrop packs (0.11/1.83 ≈ 0.06) stay below and keep 3/4 framing.
    private static let standingThinRatio: Float = 0.08
    /// Flat ground tiles: Y vs longest.
    private static let groundThinRatio: Float = 0.02

    static let autoRotateSpinName = "autoRotateSpin"
    /// RGB axis triad at the authored glTF origin when Center is off.
    /// Lives on PreviewCamera (not PreviewFloor) so ThumbnailExtension can compile.
    static let worldOriginGizmoName = "worldOriginGizmo"
    private static let axisGizmoLength: Float = 0.2
    private static let axisGizmoThickness: Float = 0.008

    /// View-menu / Camera-pill presets. Angles are degrees for `cameraPosition`.
    /// Thin-axis override is off when applying a preset so faces stay square-on.
    enum CameraPreset: String, CaseIterable, Identifiable, Sendable {
        case front, back, left, right, top, bottom, iso

        var id: String { rawValue }

        var title: String { rawValue.capitalized }

        /// SF Symbols for the throwaway View menu (Camera pill uses `cube` for the group).
        var menuSymbol: String {
            switch self {
            case .front: "arrow.up.to.line"
            case .back: "arrow.down.to.line"
            case .left: "arrow.left.to.line"
            case .right: "arrow.right.to.line"
            case .top: "arrow.up.to.line.compact"
            case .bottom: "arrow.down.to.line.compact"
            case .iso: "cube"
            }
        }

        /// Yaw degrees: 0 = +Z (front), +90 = +X (right), ±180 = −Z (back), −90 = −X (left).
        var yawDegrees: Float {
            switch self {
            case .front, .top, .bottom: return 0
            case .back: return 180
            case .right: return 90
            case .left: return -90
            case .iso: return PreviewCamera.yawDegrees
            }
        }

        /// Pitch degrees: 0 = horizon, +90 = top-down, −90 = bottom-up.
        var pitchDegrees: Float {
            switch self {
            case .front, .back, .left, .right: return 0
            case .top: return 90
            case .bottom: return -90
            case .iso: return PreviewCamera.pitchDegrees
            }
        }
    }

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
        fieldOfViewInDegrees: Float = defaultFieldOfViewDegrees
    ) {
        guard !bounds.isEmpty else { return }
        let center = (bounds.min + bounds.max) * 0.5
        // Pivot stays at the visual center (usually world origin after turntable).
        orbitFocus?.setPosition(.zero, relativeTo: nil)
        let fov = clampedFieldOfView(fieldOfViewInDegrees)
        let fitted = makeFrontThreeQuarter(
            minBound: bounds.min,
            maxBound: bounds.max,
            padding: padding,
            aspect: aspect,
            yaw: yaw,
            pitch: pitch,
            applyThinAxisOverride: applyThinAxisOverride,
            fieldOfViewInDegrees: fov
        )
        let eye = fitted.position(relativeTo: nil)
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
        fieldOfViewInDegrees: Float = defaultFieldOfViewDegrees
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
        perspective.fieldOfViewInDegrees = clampedFieldOfView(degrees)
        camera.components.set(perspective)
    }

    static func clampedFieldOfView(_ degrees: Float) -> Float {
        min(max(degrees, fieldOfViewRange.lowerBound), fieldOfViewRange.upperBound)
    }

    /// Vertical world height that fills the view for an orthographic fit of `bounds`
    /// under the default front-three-quarter look (same basis as `fitDistance`).
    static func orthographicScale(
        bounds: BoundingBox,
        aspect: Float = 1,
        padding: Float = previewFitPadding
    ) -> Float {
        orthographicScale(
            minBound: bounds.min,
            maxBound: bounds.max,
            aspect: aspect,
            padding: padding
        )
    }

    /// Vertical world height framing `bounds` for a camera at `eye` looking at `target`.
    static func orthographicScale(
        bounds: BoundingBox,
        eye: SIMD3<Float>,
        target: SIMD3<Float>,
        aspect: Float = 1,
        padding: Float = previewFitPadding
    ) -> Float {
        let offset = eye - target
        let radius = length(offset)
        guard radius > 1e-4 else {
            return orthographicScale(bounds: bounds, aspect: aspect, padding: padding)
        }
        return orthographicScale(
            extent: bounds.max - bounds.min,
            toCamera: offset / radius,
            aspect: aspect,
            padding: padding
        )
    }

    static func orthographicScale(
        minBound: SIMD3<Float>,
        maxBound: SIMD3<Float>,
        aspect: Float = 1,
        padding: Float = previewFitPadding,
        yaw: Float = yawDegrees,
        pitch: Float = pitchDegrees,
        applyThinAxisOverride: Bool = true
    ) -> Float {
        let extent = maxBound - minBound
        return orthographicScale(
            extent: extent,
            toCamera: lookDirection(
                extent: extent,
                yaw: yaw,
                pitch: pitch,
                applyThinAxisOverride: applyThinAxisOverride
            ),
            aspect: aspect,
            padding: padding
        )
    }

    /// `OrthographicCameraComponent.scale` is vertical world height; horizontal span is
    /// `scale * aspect`. Pick the larger of height-needed and width-needed/`aspect`.
    private static func orthographicScale(
        extent: SIMD3<Float>,
        toCamera: SIMD3<Float>,
        aspect: Float,
        padding: Float
    ) -> Float {
        let axes = framingAxes(toCamera: toCamera)
        let half = extent * 0.5
        let safeAspect = clampedAspect(aspect)
        let height = 2 * projectedHalf(axes.up, halfExtent: half)
        let width = 2 * projectedHalf(axes.right, halfExtent: half)
        return max(0.0001, max(height, width / safeAspect) * padding)
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

    /// A leftover mesh this many times larger than the median mesh is ignored
    /// for Fit. Typical case: Blender cm-scale helper beside a `0.01` asset.
    /// Equal-sized city tiles stay; they share one scale.
    static let outlierExtentRatio: Float = 32

    /// Union of `ModelComponent` visual bounds. Helper/empty nodes are ignored so
    /// collision boxes do not push the camera out. Falls back to the full entity
    /// if nothing has a mesh yet.
    ///
    /// For a W×H×D meters readout see `dimensions(of:relativeTo:)` / `ModelDimensions`.
    @MainActor
    static func modelBounds(of entity: Entity, relativeTo reference: Entity? = nil) -> BoundingBox {
        var boxes: [BoundingBox] = []
        func walk(_ node: Entity) {
            // Floor / selection / origin-gizmo helpers carry ModelComponents; skip
            // their subtrees so Fit framing stays on the glTF mesh only.
            // Inline names — ThumbnailExtension excludes PreviewFloor.swift.
            if node.name == "previewFloor"
                || node.name == "selectionBox"
                || node.name == worldOriginGizmoName
                || node.name == "skeletonOverlay"
                || node.name.hasPrefix("skeletonJoint")
                || node.name.hasPrefix("skeletonBone")
            {
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
    /// Standing decals (thin X or Z) look along the thin axis so the face is visible
    /// when `applyThinAxisOverride` is true (default Fit). Presets pass `false`.
    ///
    /// `yaw` / `pitch` are degrees (defaults = `yawDegrees` / `pitchDegrees`).
    static func cameraPosition(
        minBound: SIMD3<Float>,
        maxBound: SIMD3<Float>,
        padding: Float,
        aspect: Float = 1,
        yaw: Float = yawDegrees,
        pitch: Float = pitchDegrees,
        applyThinAxisOverride: Bool = true,
        fieldOfViewInDegrees: Float = defaultFieldOfViewDegrees
    ) -> SIMD3<Float> {
        let center = (minBound + maxBound) * 0.5
        let extent = maxBound - minBound
        let toCamera = lookDirection(
            extent: extent,
            yaw: yaw,
            pitch: pitch,
            applyThinAxisOverride: applyThinAxisOverride
        )
        let distance = fitDistance(
            extent: extent,
            toCamera: toCamera,
            aspect: aspect,
            padding: padding,
            fieldOfViewInDegrees: fieldOfViewInDegrees
        )
        return center + distance * toCamera
    }

    /// Distance that frames the model's *projected bounding box* — not its bounding
    /// sphere — so irregular shapes (a tree, a car) fill the viewport instead of
    /// floating inside the sphere's slack. Fits both the horizontal and vertical FOV.
    private static func fitDistance(
        extent: SIMD3<Float>,
        toCamera: SIMD3<Float>,
        aspect: Float,
        padding: Float,
        fieldOfViewInDegrees: Float = defaultFieldOfViewDegrees
    ) -> Float {
        let axes = framingAxes(toCamera: toCamera)
        let half = extent * 0.5
        // RealityView.make often runs before layout; a ~0 aspect used to push the
        // camera tens of kilometers away so the first frames looked empty.
        let safeAspect = clampedAspect(aspect)
        let vHalfFOV = clampedFieldOfView(fieldOfViewInDegrees) * .pi / 360
        let hHalfFOV = atan(tan(vHalfFOV) * safeAspect)
        let distanceV = projectedHalf(axes.up, halfExtent: half) / tan(vHalfFOV)
        let distanceH = projectedHalf(axes.right, halfExtent: half) / tan(hHalfFOV)
        // + depth so the near face of the box still fits, not just the center slice.
        let distance = max(distanceV, distanceH) + projectedHalf(axes.forward, halfExtent: half)
        return max(0.0001, distance * padding)
    }

    /// Unit vector from model center toward the camera for yaw/pitch (degrees).
    private static func lookDirection(
        extent: SIMD3<Float>,
        yaw: Float,
        pitch: Float,
        applyThinAxisOverride: Bool
    ) -> SIMD3<Float> {
        var yawRad = yaw * .pi / 180
        let pitchRad = pitch * .pi / 180
        if applyThinAxisOverride, let axis = thinAxis(extent) {
            if axis == 0 { yawRad = .pi / 2 }
            if axis == 2 { yawRad = 0 }
        }
        return SIMD3(
            sin(yawRad) * cos(pitchRad),
            sin(pitchRad),
            cos(yawRad) * cos(pitchRad)
        )
    }

    /// Camera-space basis for projected AABB framing. When look ‖ world +Y, pick +X as right.
    private static func framingAxes(toCamera: SIMD3<Float>) -> (
        forward: SIMD3<Float>,
        right: SIMD3<Float>,
        up: SIMD3<Float>
    ) {
        let forward = -toCamera
        var right = cross(forward, SIMD3<Float>(0, 1, 0))
        right = length(right) < 1e-4 ? SIMD3<Float>(1, 0, 0) : normalize(right)
        let up = normalize(cross(right, forward))
        return (forward, right, up)
    }

    /// Half-extent of an axis-aligned box projected onto a unit axis (closed form).
    private static func projectedHalf(_ axis: SIMD3<Float>, halfExtent: SIMD3<Float>) -> Float {
        abs(axis.x) * halfExtent.x + abs(axis.y) * halfExtent.y + abs(axis.z) * halfExtent.z
    }

    /// Layout can report ~0 before the first frame; clamp so Fit does not explode.
    private static func clampedAspect(_ aspect: Float) -> Float {
        (aspect > 0.05 && aspect < 20) ? aspect : 1
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
        fieldOfViewInDegrees: Float = defaultFieldOfViewDegrees
    ) -> PerspectiveCamera {
        let center = (minBound + maxBound) * 0.5
        let fov = clampedFieldOfView(fieldOfViewInDegrees)
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

    /// Default RealityKit far/near clips a 3 km tile or a 12 cm ashtray.
    static func applyFitClip(to camera: inout PerspectiveCameraComponent, eye: SIMD3<Float>, target: SIMD3<Float>) {
        let clip = fitClipDistances(eye: eye, target: target)
        camera.near = clip.near
        camera.far = clip.far
    }

    static func applyFitClip(to camera: inout OrthographicCameraComponent, eye: SIMD3<Float>, target: SIMD3<Float>) {
        let clip = fitClipDistances(eye: eye, target: target)
        camera.near = clip.near
        camera.far = clip.far
    }

    private static func fitClipDistances(eye: SIMD3<Float>, target: SIMD3<Float>) -> (near: Float, far: Float) {
        let distance = max(length(eye - target), 0.001)
        return (max(0.0005, distance * 0.0008), max(200, distance * 40))
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
        fieldOfViewInDegrees: Float = defaultFieldOfViewDegrees
    ) {
        preview.components.remove(OrthographicCameraComponent.self)
        var camera = preview.components[PerspectiveCameraComponent.self] ?? PerspectiveCameraComponent()
        camera.fieldOfViewInDegrees = clampedFieldOfView(fieldOfViewInDegrees)
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
