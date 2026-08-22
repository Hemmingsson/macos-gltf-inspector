import RealityKit
import simd

/// Axis-aligned model size in **meters** (glTF / RealityKit unit convention).
///
/// W×H×D maps to extent X×Y×Z from an existing `BoundingBox` (typically
/// `PreviewCamera.modelBounds`). No new bounds math — only packaging + readout.
struct ModelDimensions: Equatable, Sendable {
    var width: Float
    var height: Float
    var depth: Float

    /// `nil` when `bounds` is empty or non-finite. Axes: width=X, height=Y, depth=Z.
    init?(bounds: BoundingBox) {
        guard !bounds.isEmpty else { return nil }
        let extent = bounds.max - bounds.min
        guard extent.x.isFinite, extent.y.isFinite, extent.z.isFinite else { return nil }
        width = extent.x
        height = extent.y
        depth = extent.z
    }

    /// Main-html style bottom-right readout: `1.24 × 0.86 × 1.10 m`.
    var readout: String {
        String(format: "%.2f × %.2f × %.2f m", width, height, depth)
    }
}

extension PreviewCamera {
    /// W×H×D from `modelBounds` of `entity`, in meters.
    @MainActor
    static func dimensions(
        of entity: Entity,
        relativeTo reference: Entity? = nil
    ) -> ModelDimensions? {
        ModelDimensions(bounds: modelBounds(of: entity, relativeTo: reference))
    }
}
