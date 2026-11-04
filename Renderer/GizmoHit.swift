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

/// Projects world `position` through the same clip transform as overlay lines, then into view
/// points (y down). Returns nil when `w <= 0` (behind the camera).
func gizmoProject(
    _ position: SIMD3<Float>,
    viewProjection: simd_float4x4,
    viewport: GizmoHitViewport
) -> SIMD2<Float>? {
    let clip = viewProjection * SIMD4(position, 1)
    guard clip.w > 0 else { return nil }
    let ndc = SIMD3(clip.x, clip.y, clip.z) / clip.w
    let x = viewport.originX + (ndc.x + 1) * 0.5 * viewport.contentWidth
    let yFromBottom = viewport.originYFromBottom + (ndc.y + 1) * 0.5 * viewport.contentHeight
    let yDown = viewport.height - yFromBottom
    return SIMD2(x, yDown)
}

private func distanceSquaredPointToSegment(_ p: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
    let ab = b - a
    let lenSq = simd_length_squared(ab)
    if lenSq < 1e-12 { return simd_length_squared(p - a) }
    let t = simd_clamp(simd_dot(p - a, ab) / lenSq, 0, 1)
    return simd_length_squared(p - (a + t * ab))
}

private func segmentIsOffscreen(_ a: SIMD2<Float>, _ b: SIMD2<Float>, viewport: GizmoHitViewport, margin: Float) -> Bool {
    let minX = -margin, maxX = viewport.width + margin
    let minY = -margin, maxY = viewport.height + margin
    func outside(_ p: SIMD2<Float>) -> Bool {
        p.x < minX || p.x > maxX || p.y < minY || p.y > maxY
    }
    return outside(a) && outside(b)
}

/// Nearest camera/light gizmo segment within `hitSlop` view **points** of `point`, or nil.
/// Tie-break: smaller distance, then lower `nodeIndex`.
public func gizmoHit(
    at point: SIMD2<Float>,
    segments: [MetalGizmoSegment],
    viewProjection: simd_float4x4,
    viewport: GizmoHitViewport,
    hitSlop: Float = 6
) -> Int? {
    let slopSq = hitSlop * hitSlop
    var bestIndex: Int?
    var bestDistSq = Float.greatestFiniteMagnitude
    for segment in segments {
        guard let a = gizmoProject(segment.a, viewProjection: viewProjection, viewport: viewport),
              let b = gizmoProject(segment.b, viewProjection: viewProjection, viewport: viewport)
        else { continue }
        if segmentIsOffscreen(a, b, viewport: viewport, margin: hitSlop) { continue }
        let distSq = distanceSquaredPointToSegment(point, a, b)
        guard distSq <= slopSq else { continue }
        if distSq < bestDistSq - 1e-6 || (abs(distSq - bestDistSq) <= 1e-6 && (bestIndex.map { segment.nodeIndex < $0 } ?? true)) {
            bestDistSq = distSq
            bestIndex = segment.nodeIndex
        }
    }
    return bestIndex
}
