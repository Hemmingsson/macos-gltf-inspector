import GLTFCore

// Display names for values that live in GLTFCore without UI strings of their own.
// `LightingEnvironment` and `RenderLook.ToneMapping` name themselves; camera presets live on
// `CameraPreset` in Renderer.

extension RenderViewMode {
    var title: String {
        switch self {
        case .shaded: "Shaded"
        case .wireframe: "Wireframe"
        case .channel(let channel): channel.title
        }
    }

    /// SF Symbol fallback when no Spline catalog glyph is mapped.
    var systemImage: String {
        switch self {
        case .shaded: "circle.lefthalf.filled"
        case .wireframe: "grid"
        case .channel(let channel): channel.systemImage
        }
    }
}

extension RenderViewMode.Channel {
    var title: String {
        switch self {
        case .baseColor: "Base Color"
        case .metallic: "Metallic"
        case .roughness: "Roughness"
        case .normals: "Normals"
        case .tangents: "Tangents"
        case .textureCoordinates: "UVs"
        case .ambientOcclusion: "Ambient Occlusion"
        case .emissive: "Emissive"
        case .alpha: "Alpha"
        case .specular: "Specular"
        case .clearcoat: "Clearcoat"
        case .clearcoatRoughness: "Clearcoat Roughness"
        case .clearcoatNormal: "Clearcoat Normal"
        }
    }

    /// Per-channel SF Symbol when the Spline asset is unavailable.
    var systemImage: String {
        switch self {
        case .baseColor: "paintpalette"
        case .metallic: "circle.bottomhalf.filled"
        case .roughness: "cloud"
        case .normals, .clearcoatNormal: "arrow.up.and.down.and.arrow.left.and.right"
        case .tangents: "arrow.left.and.right"
        case .textureCoordinates: "square.grid.3x3"
        case .ambientOcclusion: "circle.dashed"
        case .emissive: "sun.max"
        case .alpha: "square.split.2x2"
        case .specular: "sparkle"
        case .clearcoat: "circle.circle"
        case .clearcoatRoughness: "circle.circle.fill"
        }
    }
}
