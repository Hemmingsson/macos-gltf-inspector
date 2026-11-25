import Foundation
import simd

/// One pickable line of a camera or light gizmo, tagged with its glTF node index.
public struct MetalGizmoSegment: Sendable, Equatable {
    public var a: SIMD3<Float>
    public var b: SIMD3<Float>
    public var nodeIndex: Int

    public init(a: SIMD3<Float>, b: SIMD3<Float>, nodeIndex: Int) {
        self.a = a
        self.b = b
        self.nodeIndex = nodeIndex
    }
}

/// Letterboxed drawable region inside the canvas, in the same units as `gizmoHit(at:)`'s point
/// (view **points**, x right, y down from the top of the full view bounds).
public struct GizmoHitViewport: Sendable {
    public var width: Float
    public var height: Float
    public var originX: Float
    /// Metal viewport origin measured from the **bottom** of the full bounds.
    public var originYFromBottom: Float
    public var contentWidth: Float
    public var contentHeight: Float

    /// Full bounds with no letterboxing (content fills the view).
    public init(width: Float, height: Float) {
        self.width = width
        self.height = height
        originX = 0
        originYFromBottom = 0
        contentWidth = width
        contentHeight = height
    }

    /// Matches `khronosViewport` for the given pixel size, converted to view points.
    public init(viewWidthPoints: Float, viewHeightPoints: Float, contentAspect: Float?) {
        width = viewWidthPoints
        height = viewHeightPoints
        var w = Double(viewWidthPoints), h = Double(viewHeightPoints)
        if let aspect = contentAspect, aspect > 0 {
            if Double(aspect) > w / h { h = w / Double(aspect) } else { w = h * Double(aspect) }
        }
        let x = (Double(viewWidthPoints) - w) / 2
        let yFromBottom = (Double(viewHeightPoints) - h) / 2
        originX = Float(x)
        originYFromBottom = Float(yFromBottom)
        contentWidth = Float(w)
        contentHeight = Float(h)
    }
}

/// Matches the Khronos vertex shader depth remap and the pick-pass depth buffer (ANGLE-style).
private func storedSceneDepth(_ clip: SIMD4<Float>) -> Float {
    guard clip.w > 0 else { return 1 }
    return (clip.z + clip.w) / (2 * clip.w)
}

/// Projects a clip-space point into view points (y down). Returns nil when `w <= 0` (behind the camera).
private func gizmoProjectClip(_ clip: SIMD4<Float>, viewport: GizmoHitViewport) -> SIMD2<Float>? {
    guard clip.w > 0 else { return nil }
    let ndc = SIMD3(clip.x, clip.y, clip.z) / clip.w
    let x = viewport.originX + (ndc.x + 1) * 0.5 * viewport.contentWidth
    let yFromBottom = viewport.originYFromBottom + (ndc.y + 1) * 0.5 * viewport.contentHeight
    let yDown = viewport.height - yFromBottom
    return SIMD2(x, yDown)
}

private func closestPointOnSegment2D(_ p: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> (distSq: Float, t: Float) {
    let ab = b - a
    let lenSq = simd_length_squared(ab)
    if lenSq < 1e-12 { return (simd_length_squared(p - a), 0) }
    let t = simd_clamp(simd_dot(p - a, ab) / lenSq, 0, 1)
    return (simd_length_squared(p - (a + t * ab)), t)
}

/// Nearest gizmo segment within slop, with Metal depth at the closest point on the segment.
public struct GizmoHitResult: Sendable {
    public var nodeIndex: Int
    /// Stored depth in Metal's 0…1 range, matching the pick pass and overlay soft depth.
    public var depth: Float
}

/// Keeps the part of `g0 + t * (g1 - g0)` that is `>= 0` for `t` in `[tMin, tMax]` (Liang-Barsky step).
/// Returns false when no part survives.
private func clipParameter(_ g0: Float, _ g1: Float, tMin: inout Float, tMax: inout Float) -> Bool {
    if g0 < 0 && g1 < 0 { return false }
    if g0 < 0 {
        tMin = max(tMin, g0 / (g0 - g1))
    } else if g1 < 0 {
        tMax = min(tMax, g0 / (g0 - g1))
    }
    return tMin <= tMax
}

/// Clips the clip-space segment `a`→`b` to the OpenGL clip volume `-w <= z <= w`, the same volume
/// overlay lines are drawn in. x and y are not clipped; off-viewport endpoints are handled by the
/// 2D distance test. Returns the surviving endpoints, or nil when nothing is inside.
private func clipSegmentToDepthRange(_ a: SIMD4<Float>, _ b: SIMD4<Float>) -> (SIMD4<Float>, SIMD4<Float>)? {
    var tMin: Float = 0, tMax: Float = 1
    guard clipParameter(a.z + a.w, b.z + b.w, tMin: &tMin, tMax: &tMax),
          clipParameter(a.w - a.z, b.w - b.z, tMin: &tMin, tMax: &tMax)
    else { return nil }
    let d = b - a
    return (a + tMin * d, a + tMax * d)
}

/// Nearest camera/light gizmo segment within `hitSlop` view **points** of `point`, or nil.
/// Tie-break: smaller distance, then lower `nodeIndex`.
public func gizmoHitResult(
    at point: SIMD2<Float>,
    segments: [MetalGizmoSegment],
    viewProjection: simd_float4x4,
    viewport: GizmoHitViewport,
    hitSlop: Float = 6
) -> GizmoHitResult? {
    let slopSq = hitSlop * hitSlop
    var best: GizmoHitResult?
    var bestDistSq = Float.greatestFiniteMagnitude
    for segment in segments {
        let clipA = viewProjection * SIMD4(segment.a, 1)
        let clipB = viewProjection * SIMD4(segment.b, 1)
        guard let clipped = clipSegmentToDepthRange(clipA, clipB),
              let a = gizmoProjectClip(clipped.0, viewport: viewport),
              let b = gizmoProjectClip(clipped.1, viewport: viewport)
        else { continue }
        let (distSq, t) = closestPointOnSegment2D(point, a, b)
        guard distSq <= slopSq else { continue }
        let depthA = storedSceneDepth(clipped.0)
        let depthB = storedSceneDepth(clipped.1)
        let depth = depthA + t * (depthB - depthA)
        if distSq < bestDistSq - 1e-6 || (abs(distSq - bestDistSq) <= 1e-6 && (best.map { segment.nodeIndex < $0.nodeIndex } ?? true)) {
            bestDistSq = distSq
            best = GizmoHitResult(nodeIndex: segment.nodeIndex, depth: depth)
        }
    }
    return best
}

public func gizmoHit(
    at point: SIMD2<Float>,
    segments: [MetalGizmoSegment],
    viewProjection: simd_float4x4,
    viewport: GizmoHitViewport,
    hitSlop: Float = 6
) -> Int? {
    gizmoHitResult(at: point, segments: segments, viewProjection: viewProjection, viewport: viewport, hitSlop: hitSlop)?
        .nodeIndex
}
