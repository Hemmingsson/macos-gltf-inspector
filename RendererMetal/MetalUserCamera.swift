import Foundation
import simd

/// Hand port of the pinned Khronos `UserCamera` plus the framing rules viewer.html layers on top
/// (`fitCamera`, `includeOriginInFraming`, `applySharedFitDistance`, `applyProjection`,
/// `orbitTo`, pointer orbit/pan and wheel zoom). The page is the behavioural oracle: every
/// operation here mirrors one there, including the quirks (fit keeps the current orbit angles
/// while measuring, clip planes follow the Khronos distance rather than the padded one, wheel
/// zoom refits the planes but not the orthographic scale).
///
/// The Khronos transform is always `R_y(rotAroundY) · R_x(rotAroundX)` with a translation, so it
/// is stored as angles plus camera position, which `pose` turns into the renderer's orbit pose.
public struct MetalUserCamera: Sendable, Equatable {
    /// Radians, as `UserCamera.rotAroundY` / `rotAroundX`.
    public var rotAroundY = 0.0
    public var rotAroundX = 0.0
    /// Translation of the camera transform.
    public var position = SIMD3<Double>(0, 0, 0)
    public var distance = 1.0
    public var baseDistance = 1.0
    public var panSpeed = 1.0
    /// `perspective.yfov` in radians and the clip planes the page reports.
    public var yfov = 45 * Double.pi / 180
    public var znear = 0.01
    public var zfar = Double.infinity
    /// `perspective.aspectRatio`: undefined until the first frame, then the canvas aspect of the
    /// last frame drawn with this camera (`drawScene` assigns it).
    public var aspectRatio: Double?
    /// `camera.sceneExtents`; zero until the first fit, as gl-matrix `vec3.create()`.
    public var sceneMin = SIMD3<Double>(0, 0, 0)
    public var sceneMax = SIMD3<Double>(0, 0, 0)
    /// `camera.type == "orthographic"` and the ortho values `applyProjection` last assigned.
    public var isOrthographic = false
    public var orthographic = MetalOrthographic(magnitude: 1, znear: 0.01, zfar: 100)

    static let panSpeedDenominator = 3500.0
    static let maxNearFarRatio = 10000.0
    /// viewer.html `FIT_PADDING`, the same as `RenderCamera.fitPadding`.
    public static let fitPadding = 1.02

    public init() {}

    // MARK: - Transform

    private var rotation: (right: SIMD3<Double>, up: SIMD3<Double>, back: SIMD3<Double>) {
        let cy = cos(rotAroundY), sy = sin(rotAroundY), cx = cos(rotAroundX), sx = sin(rotAroundX)
        return (SIMD3(cy, 0, -sy), SIMD3(sy * sx, cx, cy * sx), SIMD3(sy * cx, -sx, cy * cx))
    }

    public var lookDirection: SIMD3<Double> { -simd_normalize(rotation.back) }

    /// `position + lookDirection · distance` (viewer.html `cameraState` recomputes it this way).
    public var target: SIMD3<Double> { position + lookDirection * distance }

    public mutating func setDistanceFromTarget(_ distance: Double, _ target: SIMD3<Double>) {
        position = target - lookDirection * distance
        self.distance = distance
    }

    /// `orbitTo` in viewer.html: absolute angles in degrees around `target`.
    public mutating func orbitTo(azimuth: Double, elevation: Double, distance: Double, target: SIMD3<Double>) {
        rotAroundY = azimuth * .pi / 180
        rotAroundX = elevation * .pi / 180
        setDistanceFromTarget(distance, target)
    }

    // MARK: - Pointer input (CSS pixels, y down)

    /// `UserCamera.orbit(dx, dy)` with `orbitSpeed` 1/180 rad per pixel.
    public mutating func orbit(_ x: Double, _ y: Double) {
        let target = self.target
        let limit = Double.pi / 2 - 0.01
        rotAroundY += -x / 180
        rotAroundX = min(max(rotAroundX + -y / 180, -limit), limit)
        setDistanceFromTarget(distance, target)
    }

    /// `UserCamera.pan(x, y)`; the page calls it as `pan(-dx, dy)`.
    public mutating func pan(_ x: Double, _ y: Double) {
        let axes = rotation
        let scale = panSpeed * (distance / baseDistance)
        position += simd_normalize(axes.right) * (-x * scale) + simd_normalize(axes.up) * (-y * scale)
    }

    /// `UserCamera.zoomBy(value)`; the page passes `wheel.deltaY * 0.01`.
    public mutating func zoomBy(_ value: Double) {
        let target = self.target
        var zoom = pow(distance / baseDistance, 1 / 5.0)
        zoom += 0.01 * value
        zoom = max(zoom, 0.0001)
        distance = pow(zoom, 5) * baseDistance
        setDistanceFromTarget(distance, target)
        fitCameraPlanesToExtents(sceneMin, sceneMax)
    }

    // MARK: - Framing

    /// viewer.html `fitCamera`: Khronos `fitViewToScene`, the authored origin when centring is
    /// off, then the shared padded distance at the camera's current angles. Returns the distance
    /// the page records as `fitDistance` (100% zoom).
    @discardableResult
    public mutating func fit(extents: (min: SIMD3<Double>, max: SIMD3<Double>), centered: Bool, aspect: Double) -> Double? {
        // A non-finite box (Draco accessors arrive without min/max) must not move the camera:
        // the assignments below would store NaN and the next still would be empty.
        guard extents.min.x.isFinite, extents.min.y.isFinite, extents.min.z.isFinite,
              extents.max.x.isFinite, extents.max.y.isFinite, extents.max.z.isFinite else { return nil }
        sceneMin = extents.min
        sceneMax = extents.max
        fitDistanceToExtents(sceneMin, sceneMax)
        fitCameraTargetToExtents(sceneMin, sceneMax)
        fitPanSpeedToScene(sceneMin, sceneMax)
        fitCameraPlanesToExtents(sceneMin, sceneMax)
        if !centered {
            sceneMin = simd_min(sceneMin, .zero)
            sceneMax = simd_max(sceneMax, .zero)
            fitDistanceToExtents(sceneMin, sceneMax)
            fitCameraTargetToExtents(sceneMin, sceneMax)
            fitPanSpeedToScene(sceneMin, sceneMax)
            fitCameraPlanesToExtents(sceneMin, sceneMax)
        }
        let fitted = applySharedFitDistance(aspect: aspect)
        applyProjection()
        return fitted
    }

    /// viewer.html `applySharedFitDistance`: projected-AABB + near-face + 1.02, at the current angles.
    @discardableResult
    public mutating func applySharedFitDistance(aspect: Double) -> Double? {
        let extent = sceneMax - sceneMin
        let target = self.target
        let toCamera = SIMD3(sin(rotAroundY) * cos(rotAroundX), -sin(rotAroundX), cos(rotAroundY) * cos(rotAroundX))
        let distance = Self.sharedFitDistance(extent: extent, toCamera: toCamera, aspect: aspect,
                                              fieldOfViewDegrees: yfov * 180 / .pi)
        guard distance.isFinite else { return nil }
        setDistanceFromTarget(distance, target)
        baseDistance = distance
        return self.distance
    }

    /// viewer.html `applyProjection`: the ortho scale is restated from the current distance.
    public mutating func applyProjection(orthographic isOrthographic: Bool? = nil) {
        if let isOrthographic { self.isOrthographic = isOrthographic }
        if self.isOrthographic {
            orthographic = MetalOrthographic(magnitude: distance * tan(yfov / 2), znear: znear, zfar: zfar)
        }
    }

    public static func sharedFitDistance(extent: SIMD3<Double>, toCamera: SIMD3<Double>, aspect: Double,
                                         fieldOfViewDegrees: Double, padding: Double = fitPadding) -> Double {
        let length = simd_length(toCamera)
        let direction = length > 1e-4 ? toCamera / length : SIMD3(0, 0, 1)
        let forward = -direction
        var right = SIMD3(-forward.z, 0, forward.x)
        let rightLength = simd_length(right)
        right = rightLength < 1e-4 ? SIMD3(1, 0, 0) : right / rightLength
        let up = simd_normalize(simd_cross(right, forward))
        let half = extent * 0.5
        func projectedHalf(_ axis: SIMD3<Double>) -> Double { simd_dot(simd_abs(axis), half) }
        let safeAspect = aspect > 0.05 && aspect < 20 ? aspect : 1
        let vHalf = min(90, max(15, fieldOfViewDegrees)) * .pi / 360
        let hHalf = atan(tan(vHalf) * safeAspect)
        let distance = max(projectedHalf(up) / tan(vHalf), projectedHalf(right) / tan(hHalf)) + projectedHalf(forward)
        return max(0.0001, distance * padding)
    }

    mutating func fitDistanceToExtents(_ min: SIMD3<Double>, _ max: SIMD3<Double>) {
        let maxAxisLength = Swift.max(max.x - min.x, max.y - min.y)
        let xfov = yfov * (aspectRatio ?? 1)
        distance = Swift.max(maxAxisLength / 2 / tan(xfov / 2), maxAxisLength / 2 / tan(yfov / 2))
        baseDistance = distance
    }

    mutating func fitCameraTargetToExtents(_ min: SIMD3<Double>, _ max: SIMD3<Double>) {
        setDistanceFromTarget(distance, (max + min) / 2)
    }

    mutating func fitPanSpeedToScene(_ min: SIMD3<Double>, _ max: SIMD3<Double>) {
        panSpeed = simd_distance(min, max) / Self.panSpeedDenominator
    }

    mutating func fitCameraPlanesToExtents(_ min: SIMD3<Double>, _ max: SIMD3<Double>) {
        let longest = 10 * simd_distance(min, max)
        let far = distance + longest * 0.6
        znear = Swift.max(distance - longest * 0.6, far / Self.maxNearFarRatio)
        zfar = far
    }

    // MARK: - Renderer pose

    public var pose: MetalCameraPose {
        let target = SIMD3<Float>(self.target)
        return MetalCameraPose(azimuth: rotAroundY * 180 / .pi, elevation: rotAroundX * 180 / .pi,
                               distance: distance, target: target, yfov: yfov, znear: znear, zfar: zfar,
                               orthographic: isOrthographic ? orthographic : nil)
    }
}
