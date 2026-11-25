/// What the canvas shows: the shaded model, its wireframe, or one material/geometry channel.
public enum RenderViewMode: Sendable, Hashable, Codable {
    case shaded
    case wireframe
    /// Shaded with every triangle edge drawn over it in a flat colour.
    case wireframeOnShaded
    /// Shaded at ~40 % opacity without depth writes: hidden parts show through.
    case xray
    /// One neutral matte material on every mesh (mid grey, roughness 0.6, metallic 0).
    case clay
    case channel(Channel)

    public enum Channel: String, Sendable, Hashable, Codable, CaseIterable {
        case baseColor
        case metallic
        case roughness
        case normals
        case tangents
        case textureCoordinates
        case ambientOcclusion
        case emissive
        case alpha
        case specular
        case clearcoat
        case clearcoatRoughness
        case clearcoatNormal
    }
}

extension RenderViewMode {
    /// The display modes beside Shaded that need triangles, in menu order.
    public static let displayModes: [RenderViewMode] = [.wireframe, .wireframeOnShaded, .xray, .clay]
}
