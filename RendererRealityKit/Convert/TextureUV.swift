import simd

/// Character Creator / Sketchfab often split each UDIM tile into its own 0–1
/// texture but leave mesh UVs in tile space (`U 2–3`, `V 3–4`). RealityKit
/// clamps those, so the albedo samples the atlas edge.
enum TextureUV {
    /// Translate UVs that sit in one non-zero tile into the unit square.
    /// Spans larger than one tile (true wrap / `KHR_texture_transform` scale)
    /// are left alone.
    static func wrapSingleTile(_ uvs: [SIMD2<Float>]) -> [SIMD2<Float>] {
        guard let first = uvs.first else { return uvs }
        var minUV = first
        var maxUV = first
        for uv in uvs {
            minUV = simd_min(minUV, uv)
            maxUV = simd_max(maxUV, uv)
        }
        let span = maxUV - minUV
        if span.x > 1.001 || span.y > 1.001 { return uvs }
        let mid = (minUV + maxUV) * 0.5
        let tile = SIMD2(floor(mid.x), floor(mid.y))
        if tile == .zero { return uvs }
        return uvs.map { $0 - tile }
    }
}
