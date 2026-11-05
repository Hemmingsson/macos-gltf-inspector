import Foundation
import Metal
import simd

/// A complete camera pose, independent of model bounds and renderer implementation.
/// Orbit angles are degrees; the vertical field of view is radians, as in Khronos UserCamera.
public struct MetalCameraPose: Sendable, Equatable {
    public var azimuth: Double
    public var elevation: Double
    public var distance: Double
    public var target: SIMD3<Float>
    public var yfov: Double
    public var znear: Double
    public var zfar: Double
    /// The viewer's `camera.orthographic`, captured when it last restated the projection. Wheel
    /// zoom moves the camera without restating it, so the ortho scale and planes stay put until
    /// the next fit or camera command. Nil derives both from this pose, as `applyProjection` does.
    public var orthographic: MetalOrthographic?

    public init(
        azimuth: Double, elevation: Double, distance: Double, target: SIMD3<Float>,
        yfov: Double, znear: Double, zfar: Double, orthographic: MetalOrthographic? = nil
    ) {
        self.azimuth = azimuth
        self.elevation = elevation
        self.distance = distance
        self.target = target
        self.yfov = yfov
        self.znear = znear
        self.zfar = zfar
        self.orthographic = orthographic
    }

    /// What `applyProjection` in would assign for this pose.
    public var orthographicProjection: MetalOrthographic {
        orthographic ?? MetalOrthographic(magnitude: distance * tan(yfov / 2), znear: znear, zfar: zfar)
    }
}

/// Khronos `OrthographicCamera` as fills it: the same `xmag` and `ymag`.
public struct MetalOrthographic: Sendable, Equatable {
    public var magnitude: Double
    public var znear: Double
    public var zfar: Double
    public init(magnitude: Double, znear: Double, zfar: Double) {
        self.magnitude = magnitude; self.znear = znear; self.zfar = zfar
    }
}

/// Hand port of the pinned Khronos UserCamera's R_y · R_x transform and gl-matrix projection.
/// No Y flip is needed when drawing into a Metal render target; readback keeps its top-left row
/// order.
struct MetalCamera: Sendable {
    var pose: MetalCameraPose
    var isOrthographic = false
    var aspect: Float = 1
    /// Lens shift in clip space (NDC units): moves the projection centre without turning the
    /// camera, so the model centres in the part of the canvas no pane covers.
    var centerShift: SIMD2<Float> = .zero

    var transformMatrix: simd_float4x4 {
        let yaw = pose.azimuth * .pi / 180
        let pitch = pose.elevation * .pi / 180
        let cy = Float(cos(yaw)), sy = Float(sin(yaw))
        let cx = Float(cos(pitch)), sx = Float(sin(pitch))
        let rotation = simd_float4x4(columns: (
            SIMD4(cy, 0, -sy, 0),
            SIMD4(sy * sx, cx, cy * sx, 0),
            SIMD4(sy * cx, -sx, cy * cx, 0),
            SIMD4(0, 0, 0, 1)
        ))
        let direction = simd_normalize(SIMD3(
            rotation.columns.2.x, rotation.columns.2.y, rotation.columns.2.z
        ))
        let position = pose.target + direction * Float(pose.distance)
        var result = rotation
        result.columns.3 = SIMD4(position, 1)
        return result
    }

    var eye: SIMD3<Float> {
        let translation = transformMatrix.columns.3
        return SIMD3(translation.x, translation.y, translation.z)
    }

    var viewMatrix: simd_float4x4 { simd_inverse(transformMatrix) }

    /// WebGL clip coordinates (depth -1...1), as the Khronos renderer computes them; the vertex
    /// shader remaps depth to Metal's 0...1, as ANGLE does.
    var openGLProjectionMatrix: simd_float4x4 {
        guard centerShift != .zero else { return unshiftedProjection }
        var shift = matrix_identity_float4x4
        shift.columns.3 = SIMD4(centerShift.x, centerShift.y, 0, 1)
        return shift * unshiftedProjection
    }

    private var unshiftedProjection: simd_float4x4 {
        if !isOrthographic {
            let near = pose.znear, far = pose.zfar
            let f = 1 / tan(pose.yfov / 2)
            return simd_float4x4(columns: (
                SIMD4(Float(f) / aspect, 0, 0, 0), SIMD4(0, Float(f), 0, 0),
                SIMD4(0, 0, Float(far.isInfinite ? -1 : (far + near) / (near - far)), -1),
                SIMD4(0, 0, Float(far.isInfinite ? -2 * near : 2 * far * near / (near - far)), 0)
            ))
        }
        let ortho = pose.orthographicProjection
        let magnitude = ortho.magnitude, near = ortho.znear, far = ortho.zfar
        // Wide windows keep circles round: xmag grows with aspect, and the viewport is the
        // full canvas rather than a centred square.
        let wide = max(aspect, 0.05)
        return simd_float4x4(columns: (
            SIMD4(Float(1 / (magnitude * Double(wide))), 0, 0, 0), SIMD4(0, Float(1 / magnitude), 0, 0),
            SIMD4(0, 0, Float(2 / (near - far)), 0),
            SIMD4(0, 0, Float((near + far) / (near - far)), 1)
        ))
    }
}

/// `drawScene`'s letterbox: `gl.viewport(aspectOffsetX, aspectOffsetY, aspectWidth, aspectHeight)`
/// (GL truncates to integers and counts y from the bottom).
func khronosViewport(width: Int, height: Int, aspect: Float?) -> MTLViewport {
    var w = Double(width), h = Double(height)
    if let aspect, aspect > 0 {
        if Double(aspect) > w / h { h = w / Double(aspect) } else { w = h * Double(aspect) }
    }
    let x = Int((Double(width) - w) / 2), yFromBottom = Int((Double(height) - h) / 2)
    let iw = Int(w), ih = Int(h)
    return MTLViewport(originX: Double(x), originY: Double(height - yFromBottom - ih),
                       width: Double(iw), height: Double(ih), znear: 0, zfar: 1)
}
