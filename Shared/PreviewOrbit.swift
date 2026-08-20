import CoreGraphics
import RealityKit
import simd

/// Small helpers for posing a camera/light at an eye looking at a target.
/// Interactive orbit uses RealityKit `CameraControls.orbit` — not this type.
enum PreviewOrbit {
    /// Pose `camera` at `eye` looking at `target` with a stable Y-up basis.
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
