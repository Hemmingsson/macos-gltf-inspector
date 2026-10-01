import simd

/// Canned orbit-camera angles. File cameras are separate.
public enum CameraPreset: String, Sendable, Hashable, Codable, CaseIterable {
    case front
    case back
    case left
    case right
    case top
    case bottom
    case isometric
}

public enum RenderCamera {
    /// Vertical field of view of the orbit camera before the user changes it.
    public static let defaultFieldOfViewDegrees: Float = 35
    /// Field of view the user can pick (degrees).
    public static let fieldOfViewRange: ClosedRange<Float> = 15...90
    /// Extra distance after a projected-AABB fit so the model does not kiss the frame.
    /// Shared by RealityKit `PreviewCamera` and the WebKit page.
    public static let fitPadding: Float = 1.02

    public static func clampedFieldOfView(_ degrees: Float) -> Float {
        min(max(degrees, fieldOfViewRange.lowerBound), fieldOfViewRange.upperBound)
    }

    /// Distance from the model center to the eye that frames `extent` along `toCamera`.
    ///
    /// Projected AABB (not bounding sphere) plus the near-face depth, then `padding`.
    /// Same rule RealityKit Fit uses.
    public static func fitDistance(
        extent: SIMD3<Float>,
        toCamera: SIMD3<Float>,
        aspect: Float = 1,
        padding: Float = fitPadding,
        fieldOfViewInDegrees: Float = defaultFieldOfViewDegrees
    ) -> Float {
        let radius = length(toCamera)
        let direction = radius > 1e-4 ? toCamera / radius : SIMD3(0, 0, 1)
        let axes = framingAxes(toCamera: direction)
        let half = extent * 0.5
        let safeAspect = (aspect > 0.05 && aspect < 20) ? aspect : 1
        let vHalfFOV = clampedFieldOfView(fieldOfViewInDegrees) * .pi / 360
        let hHalfFOV = atan(tan(vHalfFOV) * safeAspect)
        let distanceV = projectedHalf(axes.up, halfExtent: half) / tan(vHalfFOV)
        let distanceH = projectedHalf(axes.right, halfExtent: half) / tan(hHalfFOV)
        let distance = max(distanceV, distanceH) + projectedHalf(axes.forward, halfExtent: half)
        return max(0.0001, distance * padding)
    }

    /// Unit vector from the target toward the eye for Khronos orbit angles (degrees).
    /// `UserCamera` places the eye at `R_y(azimuth) · R_x(elevation) · (0, 0, +d)`.
    public static func lookDirection(azimuthDegrees: Double, elevationDegrees: Double) -> SIMD3<Float> {
        let azimuth = Float(azimuthDegrees) * .pi / 180
        let elevation = Float(elevationDegrees) * .pi / 180
        return SIMD3(
            sin(azimuth) * cos(elevation),
            -sin(elevation),
            cos(azimuth) * cos(elevation)
        )
    }

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

    private static func projectedHalf(_ axis: SIMD3<Float>, halfExtent: SIMD3<Float>) -> Float {
        abs(axis.x) * halfExtent.x + abs(axis.y) * halfExtent.y + abs(axis.z) * halfExtent.z
    }
}
