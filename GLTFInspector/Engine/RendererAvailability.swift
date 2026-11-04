import GLTFCore
import PreviewUI

/// "Show only what the model has" narrowed to what the mounted renderer can do (its framework's
/// `features`). A control the renderer cannot drive is absent, not inert.
struct RendererAvailability: Availability {
    let model: EngineSceneModel
    /// Channels the file has data for; the base modes are prepended.
    let channels: [DebugChannel]
    let features: Set<RendererFeature>

    /// `viewModes` are the file's modes (`PreviewSession.viewModes`).
    init(model: EngineSceneModel, viewModes: [RenderViewMode], features: Set<RendererFeature>) {
        self.model = model
        self.channels = features.contains(.debugChannels) ? EngineSceneModel.mapDebugChannels(viewModes) : []
        self.features = features
    }

    var hasAnimations: Bool { !model.animations.isEmpty && features.contains(.animationPlayback) }
    /// Only gates the file-lights toggle.
    var hasLights: Bool { !model.lights.isEmpty && features.contains(.fileLights) }
    var availableDebugChannels: [ViewMode] {
        (ViewMode.base + channels.map(ViewMode.channel)).filter { $0 != .wireframe || features.contains(.wireframe) }
    }
}
