import GLTFCore
import PreviewUI

/// PreviewUI seam values ↔ GLTFCore render values, one switch per type.
///
/// PreviewUI never imports GLTFCore (and the extensions never link PreviewUI), so the host is the
/// only place both vocabularies meet.
extension RenderViewMode {
    init(_ mode: ViewMode) {
        switch mode {
        case .shaded: self = .shaded
        case .wireframe: self = .wireframe
        case .channel(let channel): self = .channel(Channel(channel))
        }
    }
}

extension ViewMode {
    init(_ mode: RenderViewMode) {
        switch mode {
        case .shaded: self = .shaded
        case .wireframe: self = .wireframe
        case .channel(let channel): self = .channel(DebugChannel(channel))
        }
    }
}

extension RenderViewMode.Channel {
    init(_ channel: DebugChannel) {
        switch channel {
        case .baseColor: self = .baseColor
        case .metallic: self = .metallic
        case .roughness: self = .roughness
        case .normals: self = .normals
        case .tangents: self = .tangents
        case .textureCoordinates: self = .textureCoordinates
        case .ambientOcclusion: self = .ambientOcclusion
        case .emissive: self = .emissive
        case .alpha: self = .alpha
        case .specular: self = .specular
        case .clearcoat: self = .clearcoat
        case .clearcoatRoughness: self = .clearcoatRoughness
        case .clearcoatNormal: self = .clearcoatNormal
        }
    }
}

extension DebugChannel {
    init(_ channel: RenderViewMode.Channel) {
        switch channel {
        case .baseColor: self = .baseColor
        case .metallic: self = .metallic
        case .roughness: self = .roughness
        case .normals: self = .normals
        case .tangents: self = .tangents
        case .textureCoordinates: self = .textureCoordinates
        case .ambientOcclusion: self = .ambientOcclusion
        case .emissive: self = .emissive
        case .alpha: self = .alpha
        case .specular: self = .specular
        case .clearcoat: self = .clearcoat
        case .clearcoatRoughness: self = .clearcoatRoughness
        case .clearcoatNormal: self = .clearcoatNormal
        }
    }
}

extension GLTFCore.CameraPreset {
    init(_ preset: PreviewUI.CameraPreset) {
        switch preset {
        case .front: self = .front
        case .back: self = .back
        case .left: self = .left
        case .right: self = .right
        case .top: self = .top
        case .bottom: self = .bottom
        case .isometric: self = .isometric
        }
    }
}

extension PreviewUI.CameraPreset {
    init(_ preset: GLTFCore.CameraPreset) {
        switch preset {
        case .front: self = .front
        case .back: self = .back
        case .left: self = .left
        case .right: self = .right
        case .top: self = .top
        case .bottom: self = .bottom
        case .isometric: self = .isometric
        }
    }
}

extension RenderLook.ToneMapping {
    init(_ toneMapping: ToneMapping) {
        switch toneMapping {
        case .neutral: self = .pbrNeutral
        case .acesHill: self = .acesHill
        case .acesNarkowicz: self = .acesNarkowicz
        case .linear: self = .none
        }
    }
}

extension KhronosEnvironments {
    init(_ environment: StudioEnvironment) {
        switch environment {
        case .neutral: self = .studioNeutral
        case .field: self = .field
        case .colorfulStudio: self = .colorfulStudio
        }
    }
}

extension RenderLook.Color {
    /// Same values the web canvas clears to (`WebPreviewCanvas.Look`): alpha 0 for `window`.
    init(_ backdrop: BackdropStyle) {
        switch backdrop {
        case .window: self = .clear
        case .white: self.init(red: 1, green: 1, blue: 1, alpha: 1)
        case .dark: self.init(red: 0.09, green: 0.09, blue: 0.10, alpha: 1)
        }
    }
}

extension RenderLook {
    /// The seam's lighting + backdrop as one look. Yaw passes through unchanged: the seam's 0 is
    /// meant as the Khronos default view; any per-renderer offset lives in that renderer's mapping.
    init(_ lighting: LightingSettings, backdrop: BackdropStyle) {
        self.init(
            exposureEV: lighting.exposure,
            environmentIntensity: 1,
            environmentYawDegrees: lighting.environmentRotationDegrees,
            usesEnvironment: lighting.usesStudioEnvironment,
            environment: KhronosEnvironments(lighting.environment),
            toneMapping: ToneMapping(lighting.toneMapping),
            background: Color(backdrop),
            usesFileLights: lighting.usesFileLights
        )
    }
}
