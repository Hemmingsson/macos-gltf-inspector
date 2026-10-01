import Foundation

/// Backdrop behind the model. Mirrors the host's stored backgrounds.
public enum BackdropStyle: String, Sendable, Hashable, Codable, CaseIterable, Identifiable {
    case window
    case white
    case dark

    public var id: Self { self }

    public var title: String {
        switch self {
        case .window: "None"
        case .white: "White"
        case .dark: "Dark"
        }
    }
}

/// A render channel the view-mode menu can offer. Only channels the file actually
/// has appear (`Availability.availableDebugChannels`).
public enum DebugChannel: String, Sendable, Hashable, Codable, CaseIterable, Identifiable {
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

    public var id: Self { self }

    public var title: String {
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

/// How the canvas draws the model. Menu shows full names, never abbreviations.
public enum ViewMode: Sendable, Hashable, Identifiable {
    case shaded
    case wireframe
    case channel(DebugChannel)

    public var id: String {
        switch self {
        case .shaded: "shaded"
        case .wireframe: "wireframe"
        case .channel(let channel): "channel.\(channel.rawValue)"
        }
    }

    public var title: String {
        switch self {
        case .shaded: "Shaded"
        case .wireframe: "Wireframe"
        case .channel(let channel): channel.title
        }
    }

    /// Always-available modes; channels are appended per file.
    public static let base: [ViewMode] = [.shaded, .wireframe]
}

public enum Projection: String, Sendable, Hashable, Codable, CaseIterable, Identifiable {
    case perspective
    case orthographic

    public var id: Self { self }

    public var title: String {
        switch self {
        case .perspective: "Perspective"
        case .orthographic: "Orthographic"
        }
    }
}

/// Canned camera angles. File cameras are separate (`SceneModel.cameras`).
public enum CameraPreset: String, Sendable, Hashable, Codable, CaseIterable, Identifiable {
    case front
    case back
    case left
    case right
    case top
    case bottom
    case isometric

    public var id: Self { self }

    public var title: String {
        switch self {
        case .front: "Front"
        case .back: "Back"
        case .left: "Left"
        case .right: "Right"
        case .top: "Top"
        case .bottom: "Bottom"
        case .isometric: "Isometric"
        }
    }
}

/// The bundled image-based lighting environments.
///
/// glTF files carry no environment of their own, so what a model looks like is partly the app's
/// choice. Naming that choice and putting it on screen is the honest option: a user comparing
/// against another tool needs to know what they are comparing.
public enum StudioEnvironment: String, Sendable, Hashable, CaseIterable, Identifiable {
    case neutral
    case field
    case colorfulStudio = "Colorful_Studio"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .neutral: "Neutral"
        case .field: "Field"
        case .colorfulStudio: "Studio"
        }
    }
}

/// Tone mapping curve applied on the way to the screen.
///
/// `neutral` is the default on purpose: Khronos designed PBR Neutral for asset review because it
/// distorts authored colour least. ACES looks more cinematic and is the wrong default for a tool
/// whose job is telling you what is actually in the file.
public enum ToneMapping: String, Sendable, Hashable, CaseIterable, Identifiable {
    case neutral
    case acesHill
    case acesNarkowicz
    case linear

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .neutral: "Neutral"
        case .acesHill: "ACES"
        case .acesNarkowicz: "ACES Fast"
        case .linear: "Linear"
        }
    }

    /// Persisted and sent to the renderer as this exact string — the renderer matches on it, and
    /// the sandboxed extensions read the stored value without linking this framework.
    public var khronosName: String {
        switch self {
        case .neutral: "Khronos PBR Neutral"
        case .acesHill: "ACES Filmic Tone Mapping (Hill)"
        case .acesNarkowicz: "ACES Filmic Tone Mapping (Narkowicz)"
        case .linear: "None (Linear mapping, clamped at 1.0)"
        }
    }

    public static func fromKhronosName(_ name: String) -> ToneMapping {
        allCases.first { $0.khronosName == name } ?? .neutral
    }
}

/// What the lighting popover edits.
public struct LightingSettings: Sendable, Hashable {
    /// Exposure compensation in stops.
    public var exposure: Double
    /// Environment yaw in degrees.
    public var environmentRotationDegrees: Double
    /// Use the file's punctual lights (only meaningful when `Availability.hasLights`).
    public var usesFileLights: Bool
    /// Use the bundled studio IBL.
    public var usesStudioEnvironment: Bool
    /// Which bundled IBL lights the model.
    public var environment: StudioEnvironment
    /// Tone mapping curve.
    public var toneMapping: ToneMapping

    public static let standard = LightingSettings(
        exposure: 0,
        environmentRotationDegrees: 0,
        usesFileLights: false,
        usesStudioEnvironment: true,
        environment: .neutral,
        toneMapping: .neutral
    )

    public init(
        exposure: Double,
        environmentRotationDegrees: Double,
        usesFileLights: Bool,
        usesStudioEnvironment: Bool,
        environment: StudioEnvironment = .neutral,
        toneMapping: ToneMapping = .neutral
    ) {
        self.exposure = exposure
        self.environmentRotationDegrees = environmentRotationDegrees
        self.usesFileLights = usesFileLights
        self.environment = environment
        self.toneMapping = toneMapping
        self.usesStudioEnvironment = usesStudioEnvironment
    }
}
