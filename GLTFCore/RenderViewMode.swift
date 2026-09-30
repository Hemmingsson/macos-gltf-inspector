/// What the canvas shows: the shaded model, its wireframe, or one material/geometry channel.
public enum RenderViewMode: Sendable, Hashable, Codable {
    case shaded
    case wireframe
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
