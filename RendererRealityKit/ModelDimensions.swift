import RealityKit
import simd

/// Axis-aligned model size in **meters** (glTF / RealityKit unit convention).
///
/// W×H×D maps to extent X×Y×Z from an existing `BoundingBox` (typically
/// `PreviewCamera.modelBounds`). No new bounds math — only packaging + readout.
public struct ModelDimensions: Equatable, Sendable {
    public var width: Float
    public var height: Float
    public var depth: Float

    /// `nil` when `bounds` is empty or non-finite. Axes: width=X, height=Y, depth=Z.
    init?(bounds: BoundingBox) {
        guard !bounds.isEmpty else { return nil }
        let extent = bounds.max - bounds.min
        guard extent.x.isFinite, extent.y.isFinite, extent.z.isFinite else { return nil }
        width = extent.x
        height = extent.y
        depth = extent.z
    }

    /// Bottom-right readout, e.g. `1.24 × 0.86 × 1.10 m`.
    public var readout: String {
        String(format: "%.2f × %.2f × %.2f m", width, height, depth)
    }
}
