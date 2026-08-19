import RealityKit

/// Thumbnail path no longer flattens PBR; authored materials stay as loaded.
enum GLBThumbnailPrepare {
    @MainActor
    static func apply(to _: Entity) {}
}
