import Foundation
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

    public init(
        azimuth: Double, elevation: Double, distance: Double, target: SIMD3<Float>,
        yfov: Double, znear: Double, zfar: Double
    ) {
        self.azimuth = azimuth
        self.elevation = elevation
        self.distance = distance
        self.target = target
        self.yfov = yfov
        self.znear = znear
        self.zfar = zfar
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
        let near = pose.znear, far = pose.zfar
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
            let magnitude = pose.distance * tan(pose.yfov / 2)
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
        let near = pose.znear, far = pose.zfar
        if projection == .perspective {
            let f = 1 / tan(pose.yfov / 2)
            return simd_float4x4(columns: (
                SIMD4(Float(f) / aspect, 0, 0, 0), SIMD4(0, Float(f), 0, 0),
                SIMD4(0, 0, Float(far.isInfinite ? -1 : (far + near) / (near - far)), -1),
                SIMD4(0, 0, Float(far.isInfinite ? -2 * near : 2 * far * near / (near - far)), 0)
            ))
        }
        let magnitude = pose.distance * tan(pose.yfov / 2)
        return simd_float4x4(columns: (
            SIMD4(Float(1 / magnitude), 0, 0, 0), SIMD4(0, Float(1 / magnitude), 0, 0),
            SIMD4(0, 0, Float(2 / (near - far)), 0),
            SIMD4(0, 0, Float((near + far) / (near - far)), 1)
        ))
    }

    public var viewProjectionMatrix: simd_float4x4 { projectionMatrix * viewMatrix }
}
