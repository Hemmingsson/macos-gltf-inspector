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

    /// One glyph per family: the shaded sphere, a grid for wireframe, the cube for any channel.
    var systemImage: String {
        switch self {
        case .shaded: "circle.lefthalf.filled"
        case .wireframe: "grid"
        case .channel: "cube"
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
}
