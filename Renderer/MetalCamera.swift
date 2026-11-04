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
    /// The page's `camera.orthographic`, captured when it last restated the projection. Wheel
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

    /// What `applyProjection` in viewer.html would assign for this pose.
    public var orthographicProjection: MetalOrthographic {
        orthographic ?? MetalOrthographic(magnitude: distance * tan(yfov / 2), znear: znear, zfar: zfar)
    }
}

/// Khronos `OrthographicCamera` as viewer.html fills it: the same `xmag` and `ymag`.
public struct MetalOrthographic: Sendable, Equatable {
    public var magnitude: Double
    public var znear: Double
    public var zfar: Double
    public init(magnitude: Double, znear: Double, zfar: Double) {
        self.magnitude = magnitude; self.znear = znear; self.zfar = zfar
    }
}

/// Hand port of pinned Khronos UserCamera's R_y · R_x transform and gl-matrix projection.
/// Only clip depth changes: WebGL's [-w,w] becomes Metal's [0,w]. No Y flip is needed when
/// drawing a scene into a Metal render target; readback keeps its top-left row order.
public struct MetalCamera: Sendable {
    public enum Projection: Sendable { case perspective, orthographic }

    public var pose: MetalCameraPose
    public var projection: Projection
    public var aspect: Float

    public init(pose: MetalCameraPose, projection: Projection = .perspective, aspect: Float = 1) {
        self.pose = pose
        self.projection = projection
        self.aspect = aspect
    }

    public init(pose: MetalCameraPose, isOrthographic: Bool, aspect: Float) {
        self.init(pose: pose, projection: isOrthographic ? .orthographic : .perspective, aspect: aspect)
    }

    public var transformMatrix: simd_float4x4 {
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

    public var eye: SIMD3<Float> {
        let translation = transformMatrix.columns.3
        return SIMD3(translation.x, translation.y, translation.z)
    }

    public var viewMatrix: simd_float4x4 { simd_inverse(transformMatrix) }

    public var projectionMatrix: simd_float4x4 {
        var near = pose.znear, far = pose.zfar
        if projection == .orthographic { (near, far) = (pose.orthographicProjection.znear, pose.orthographicProjection.zfar) }
        switch projection {
        case .perspective:
            let f = 1 / tan(pose.yfov / 2)
            // Algebraically identical to depthRemap * gl-matrix.perspective().
            let z = far.isInfinite ? -1 : far / (near - far)
            let translation = far.isInfinite ? -near : far * near / (near - far)
            return simd_float4x4(columns: (
                SIMD4(Float(f) / aspect, 0, 0, 0),
                SIMD4(0, Float(f), 0, 0),
                SIMD4(0, 0, Float(z), -1),
                SIMD4(0, 0, Float(translation), 0)
            ))
        case .orthographic:
            // viewer.html deliberately assigns the same xmag and ymag, even on a wide canvas.
            let magnitude = pose.orthographicProjection.magnitude
            return simd_float4x4(columns: (
                SIMD4(Float(1 / magnitude), 0, 0, 0),
                SIMD4(0, Float(1 / magnitude), 0, 0),
                SIMD4(0, 0, Float(1 / (near - far)), 0),
                SIMD4(0, 0, Float(near / (near - far)), 1)
            ))
        }
    }

    /// Preserve WebGL clip coordinates until the vertex shader remaps depth, as ANGLE does.
    public var openGLProjectionMatrix: simd_float4x4 {
        if projection == .perspective {
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
        return simd_float4x4(columns: (
            SIMD4(Float(1 / magnitude), 0, 0, 0), SIMD4(0, Float(1 / magnitude), 0, 0),
            SIMD4(0, 0, Float(2 / (near - far)), 0),
            SIMD4(0, 0, Float((near + far) / (near - far)), 1)
        ))
    }

    public var viewProjectionMatrix: simd_float4x4 { projectionMatrix * viewMatrix }
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
