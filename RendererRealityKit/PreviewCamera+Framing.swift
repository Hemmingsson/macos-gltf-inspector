import GLTFCore
import RealityKit
import simd

/// Pure framing math (no entities): thin-axis look, projected-AABB fit distance,
/// orthographic scale, clip distances and the mesh-box union. `PreviewCamera.swift`
/// applies these to camera entities.
extension PreviewCamera {
    /// Standing planes (doors, decals): X or Z vs longest. 0.08 catches architectural
    /// doors; snowdrop packs (0.11/1.83 ≈ 0.06) stay below and keep 3/4 framing.
    private static let standingThinRatio: Float = 0.08
    /// Flat ground tiles: Y vs longest.
    private static let groundThinRatio: Float = 0.02

    /// Vertical world height that fills the view for an orthographic fit of `bounds`
    /// under the default front-three-quarter look (same basis as `fitDistance`).
    static func orthographicScale(
        bounds: BoundingBox,
        aspect: Float = 1,
        padding: Float = previewFitPadding
    ) -> Float {
        let extent = bounds.max - bounds.min
        return orthographicScale(
            extent: extent,
            toCamera: lookDirection(extent: extent, preset: nil),
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

    /// `OrthographicCameraComponent.scale` is vertical world height; horizontal span is
    /// `scale * aspect`. Pick the larger of height-needed and width-needed/`aspect`.
    private static func orthographicScale(
        extent: SIMD3<Float>,
        toCamera: SIMD3<Float>,
        aspect: Float,
        padding: Float
    ) -> Float {
        let height = RenderCamera.orthographicHeight(extent: extent, toCamera: toCamera, aspect: aspect)
        return max(0.0001, height * padding)
    }

    /// Keep the cluster of typical mesh sizes; drop a single km-scale leftover
    /// (the JSON-bounds rule, `ModelBounds.union`).
    static func unionModelBoxes(_ boxes: [BoundingBox]) -> BoundingBox? {
        ModelBounds.union(boxes.map { ModelBounds(min: $0.min, max: $0.max) })
            .map { BoundingBox(min: $0.min, max: $0.max) }
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
    /// when `preset` is nil (default Fit). A named preset keeps its own yaw/pitch.
    static func cameraPosition(
        minBound: SIMD3<Float>,
        maxBound: SIMD3<Float>,
        padding: Float,
        aspect: Float = 1,
        preset: CameraPreset? = nil,
        fieldOfViewInDegrees: Float = RenderCamera.defaultFieldOfViewDegrees
    ) -> SIMD3<Float> {
        let center = (minBound + maxBound) * 0.5
        let extent = maxBound - minBound
        let toCamera = lookDirection(extent: extent, preset: preset)
        let distance = RenderCamera.fitDistance(
            extent: extent,
            toCamera: toCamera,
            aspect: aspect,
            padding: padding,
            fieldOfViewInDegrees: fieldOfViewInDegrees
        )
        return center + distance * toCamera
    }

    /// Unit vector from model center toward the camera. `nil` = default front 3/4 with the
    /// thin-axis override.
    private static func lookDirection(extent: SIMD3<Float>, preset: CameraPreset?) -> SIMD3<Float> {
        var yawRad = (preset?.yawDegrees ?? yawDegrees) * .pi / 180
        let pitchRad = (preset?.pitchDegrees ?? pitchDegrees) * .pi / 180
        if preset == nil, let axis = thinAxis(extent) {
            if axis == 0 { yawRad = .pi / 2 }
            if axis == 2 { yawRad = 0 }
        }
        return SIMD3(
            sin(yawRad) * cos(pitchRad),
            sin(pitchRad),
            cos(yawRad) * cos(pitchRad)
        )
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
}

/// Preset orbit angles in degrees for `PreviewCamera.cameraPosition`.
/// Thin-axis override is off when applying a preset so faces stay square-on.
extension CameraPreset {
    /// Yaw degrees: 0 = +Z (front), +90 = +X (right), ±180 = −Z (back), −90 = −X (left).
    var yawDegrees: Float {
        switch self {
        case .front, .top, .bottom: return 0
        case .back: return 180
        case .right: return 90
        case .left: return -90
        case .isometric: return PreviewCamera.yawDegrees
        }
    }

    /// Pitch degrees: 0 = horizon, +90 = top-down, −90 = bottom-up.
    var pitchDegrees: Float {
        switch self {
        case .front, .back, .left, .right: return 0
        case .top: return 90
        case .bottom: return -90
        case .isometric: return PreviewCamera.pitchDegrees
        }
    }
}
