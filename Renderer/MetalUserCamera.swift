import Foundation
import simd

/// Orbit camera: a hand port of the Khronos Sample Viewer `UserCamera`
/// (`fitCamera`, `includeOriginInFraming`, `applySharedFitDistance`, `applyProjection`, `orbitTo`,
/// pointer orbit/pan and wheel zoom). Fit keeps the current orbit angles while measuring; clip
/// planes follow the Khronos distance rather than the padded one; wheel zoom refits the planes
/// and, through `applyProjection`, restates the orthographic scale from the new distance.
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
    /// `perspective.yfov` in radians and the clip planes the viewer reports.
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
    /// `FIT_PADDING`, the same as `RenderCamera.fitPadding`.
    public static let fitPadding = 1.02

    public init() {}

    // MARK: - Transform

    private var rotation: (right: SIMD3<Double>, up: SIMD3<Double>, back: SIMD3<Double>) {
        let cy = cos(rotAroundY), sy = sin(rotAroundY), cx = cos(rotAroundX), sx = sin(rotAroundX)
        return (SIMD3(cy, 0, -sy), SIMD3(sy * sx, cx, cy * sx), SIMD3(sy * cx, -sx, cy * cx))
    }

    public var lookDirection: SIMD3<Double> { -simd_normalize(rotation.back) }

    /// `position + lookDirection · distance` (`cameraState` recomputes it this way).
    public var target: SIMD3<Double> { position + lookDirection * distance }

    public mutating func setDistanceFromTarget(_ distance: Double, _ target: SIMD3<Double>) {
        position = target - lookDirection * distance
        self.distance = distance
    }

    /// `orbitTo` in the viewer: absolute angles in degrees around `target`.
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

    /// `UserCamera.pan(x, y)`; the viewer calls it as `pan(-dx, dy)`.
    public mutating func pan(_ x: Double, _ y: Double) {
        let axes = rotation
        let scale = panSpeed * (distance / baseDistance)
        position += simd_normalize(axes.right) * (-x * scale) + simd_normalize(axes.up) * (-y * scale)
    }

    /// `UserCamera.zoomBy(value)`; the viewer passes `wheel.deltaY * 0.01`.
    public mutating func zoomBy(_ value: Double) {
        let target = self.target
        var zoom = pow(distance / baseDistance, 1 / 5.0)
        zoom += 0.01 * value
        zoom = max(zoom, 0.0001)
        distance = pow(zoom, 5) * baseDistance
        setDistanceFromTarget(distance, target)
        fitCameraPlanesToExtents(sceneMin, sceneMax)
    }

    // MARK: - Viewer essentials: pivot and pointer zoom

    /// `orbit(x, y)` about `pivot` instead of the target: the whole camera turns rigidly about the
    /// pivot, so the pivot keeps its place on screen and nothing jumps when the pivot is off-centre
    /// (after a pan or pointer zoom). Distance is kept; the target stays on the look axis.
    /// Works the same in orthographic, where the view-space position of the pivot is all that shows.
    public mutating func orbit(_ x: Double, _ y: Double, around pivot: SIMD3<Double>) {
        let before = rotation
        let offset = position - pivot
        let local = SIMD3(simd_dot(offset, before.right), simd_dot(offset, before.up), simd_dot(offset, before.back))
        let limit = Double.pi / 2 - 0.01
        rotAroundY += -x / 180
        rotAroundX = min(max(rotAroundX + -y / 180, -limit), limit)
        let after = rotation
        position = pivot + after.right * local.x + after.up * local.y + after.back * local.z
        fitCameraPlanesToExtents(sceneMin, sceneMax)
    }

    /// Where the orbit target moves so `pointer` (a world point on the target's view plane)
    /// stays under the cursor after the distance scales by `factor` (new / old).
    public static func pointerDollyTarget(target: SIMD3<Double>, pointer: SIMD3<Double>, factor: Double) -> SIMD3<Double> {
        target + (pointer - target) * (1 - factor)
    }

    /// `zoomBy`, then slides the target (and eye with it) so `pointer` stays put on screen.
    public mutating func zoomBy(_ value: Double, toward pointer: SIMD3<Double>) {
        let before = distance
        zoomBy(value)
        guard before > 0, distance.isFinite else { return }
        let moved = Self.pointerDollyTarget(target: target, pointer: pointer, factor: distance / before)
        setDistanceFromTarget(distance, moved)
    }

    // MARK: - Framing

    /// `fitCamera`: Khronos `fitViewToScene`, the authored origin when centring is
    /// off, then the shared padded distance at the camera's current angles. Returns the distance
    /// the viewer records as `fitDistance` (100% zoom).
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

    /// Selection framing (`ModelView.frame`): moves the orbit target to the centre of `box` and
    /// dollies to the shared padded distance for it at the current angles. Unlike `fit`, it keeps
    /// the scene extents, pan speed and zoom base, so floor, gizmos and zoom stay scene-relative.
    /// The clip planes still cover the whole scene from the new eye. Returns the framed distance.
    @discardableResult
    public mutating func frame(box: (min: SIMD3<Double>, max: SIMD3<Double>), aspect: Double) -> Double? {
        guard box.min.x.isFinite, box.min.y.isFinite, box.min.z.isFinite,
              box.max.x.isFinite, box.max.y.isFinite, box.max.z.isFinite else { return nil }
        // Point-sized or flat boxes (cameras, lights, empties, joints, zero-area meshes) get a
        // finite volume: each thin axis is widened to 15% of the scene span, as the gizmos are.
        let minimumSpan = max(simd_length(sceneMax - sceneMin) * Self.minimumFramingFraction, 1e-3)
        let centre = (box.min + box.max) / 2
        let half = simd_max((box.max - box.min) / 2, SIMD3(repeating: minimumSpan / 2))
        let framed = (min: centre - half, max: centre + half)
        let toCamera = SIMD3(sin(rotAroundY) * cos(rotAroundX), -sin(rotAroundX), cos(rotAroundY) * cos(rotAroundX))
        let distance = Self.sharedFitDistance(extent: framed.max - framed.min, toCamera: toCamera, aspect: aspect,
                                              fieldOfViewDegrees: yfov * 180 / .pi)
        guard distance.isFinite else { return nil }
        setDistanceFromTarget(distance, centre)
        fitCameraPlanesToExtents(simd_min(sceneMin, framed.min), simd_max(sceneMax, framed.max))
        // Keep the planes valid: 0 < znear < zfar, both finite, whatever the scene looked like.
        if !(zfar.isFinite && znear.isFinite && znear > 0 && znear < zfar) {
            zfar = max(distance * 2, 1e-3)
            znear = zfar / Self.maxNearFarRatio
        }
        applyProjection()
        return distance
    }

    /// The authored origin sits outside the model: the box is clear of the origin by a quarter
    /// of its diagonal. A model that contains the origin, or merely touches it, is not far.
    public static func originIsFarFromModel(min: SIMD3<Double>, max: SIMD3<Double>) -> Bool {
        let span = max - min
        let pad = Swift.max(simd_length(span) * 0.25, 1e-4)
        guard pad.isFinite else { return false }
        return min.x > pad || max.x < -pad || min.y > pad || max.y < -pad || min.z > pad || max.z < -pad
    }

    /// Gizmo span as a fraction of the scene span (`ModelView` gizmo sizing).
    static let minimumFramingFraction = 0.15

    /// `applySharedFitDistance`: projected-AABB + near-face + 1.02, at the current angles.
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

    /// `applyProjection`: the ortho scale is restated from the current distance.
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
        let vHalf = min(160, max(15, fieldOfViewDegrees)) * .pi / 360
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
