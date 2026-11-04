import GLTFCore
import Renderer

// What the menus, pickers and inspector call the renderer's and the file's values. Full names,
// never abbreviations (DESIGN.md).

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

extension CameraPreset: @retroactive Identifiable {
    public var id: Self { self }

    var title: String { rawValue.capitalized }

    var systemImage: String {
        switch self {
        case .front: "arrow.up.to.line"
        case .back: "arrow.down.to.line"
        case .left: "arrow.left.to.line"
        case .right: "arrow.right.to.line"
        case .top: "arrow.up.to.line.compact"
        case .bottom: "arrow.down.to.line.compact"
        case .isometric: "cube"
        }
    }
}

/// glTF files carry no environment of their own, so what a model looks like is partly the app's
/// choice; naming it on screen lets a user know what they compare against.
extension KhronosEnvironments: @retroactive Identifiable {
    public var id: Self { self }

    /// Short name for the lighting popover.
    var title: String {
        switch self {
        case .studioNeutral: "Neutral"
        case .field: "Field"
        case .colorfulStudio: "Studio"
        }
    }

    /// Full Khronos name for Settings.
    var fullTitle: String {
        switch self {
        case .studioNeutral: "Studio Neutral"
        case .field: "Field"
        case .colorfulStudio: "Colorful Studio"
        }
    }
}

/// Khronos PBR Neutral is the default on purpose: it was designed for asset review and distorts
/// authored colour least. ACES is offered because many DCC tools show it.
extension RenderLook.ToneMapping: @retroactive Identifiable {
    public var id: Self { self }

    var title: String {
        switch self {
        case .pbrNeutral: "Neutral"
        case .acesHill: "ACES"
        case .acesNarkowicz: "ACES Fast"
        case .none: "Linear"
        }
    }
}
