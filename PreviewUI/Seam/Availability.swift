import Foundation

/// Drives "show only what the model has" (DESIGN.md). Every adaptive section and control
/// reads its visibility from here — never from a hard-coded `if` in a view.
protocol Availability: Sendable {
    var hasAnimations: Bool { get }
    var hasLights: Bool { get }
    var hasCameras: Bool { get }
    var isMultiScene: Bool { get }
    var hasSkin: Bool { get }
    var hasMorphs: Bool { get }
    /// View modes the file can actually render, in menu order. Always starts with the
    /// base modes; channels the file lacks are absent, not disabled.
    var availableDebugChannels: [ViewMode] { get }
}

/// Availability computed straight from a `SceneModel`.
struct DerivedAvailability<Model: SceneModel>: Availability {
    var model: Model
    /// Channels the file has data for; the base modes are prepended.
    var channels: [DebugChannel]

    init(model: Model, channels: [DebugChannel] = DebugChannel.allCases) {
        self.model = model
        self.channels = channels
    }

    var hasAnimations: Bool { !model.animations.isEmpty }
    var hasLights: Bool { !model.lights.isEmpty }
    var hasCameras: Bool { !model.cameras.isEmpty }
    var isMultiScene: Bool { model.scenes.count > 1 }
    var hasSkin: Bool { !model.skins.isEmpty }
    var hasMorphs: Bool { !model.morphs.isEmpty }
    var availableDebugChannels: [ViewMode] { ViewMode.base + channels.map(ViewMode.channel) }
}
