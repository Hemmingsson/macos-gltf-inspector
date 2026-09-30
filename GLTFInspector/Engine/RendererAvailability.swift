import GLTFCore
import PreviewUI

/// "Show only what the model has" (`DerivedAvailability`) narrowed to what the mounted renderer
/// can do (its framework's `features`). A control the renderer cannot drive is absent, not inert.
struct RendererAvailability: Availability {
    let file: DerivedAvailability<EngineSceneModel>
    let features: Set<RendererFeature>

    /// `viewModes` are the file's modes (`PreviewSession.viewModes`).
    init(model: EngineSceneModel, viewModes: [RenderViewMode], features: Set<RendererFeature>) {
        let channels = features.contains(.debugChannels) ? EngineSceneModel.mapDebugChannels(viewModes) : []
        self.file = DerivedAvailability(model: model, channels: channels)
        self.features = features
    }

    var hasAnimations: Bool { file.hasAnimations && features.contains(.animationPlayback) }
    /// Only gates the file-lights toggle.
    var hasLights: Bool { file.hasLights && features.contains(.fileLights) }
    var hasCameras: Bool { file.hasCameras }
    var isMultiScene: Bool { file.isMultiScene }
    var hasSkin: Bool { file.hasSkin }
    var hasMorphs: Bool { file.hasMorphs && features.contains(.morphTargets) }
    var availableDebugChannels: [ViewMode] {
        file.availableDebugChannels.filter { $0 != .wireframe || features.contains(.wireframe) }
    }
    /// Hide / solo in the outliner (`EngineSelectionModel.canHideNodes`).
    var canHideNodes: Bool { features.contains(.nodeVisibility) }
}
