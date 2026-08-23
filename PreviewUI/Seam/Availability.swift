import Foundation

/// Drives "show only what the model has" (DESIGN.md). Every adaptive section and control
/// reads its visibility from here — never from a hard-coded `if` in a view.
public protocol Availability: Sendable {
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
public struct DerivedAvailability<Model: SceneModel>: Availability {
    public var model: Model
    /// Channels the file has data for; the base modes are prepended.
    public var channels: [DebugChannel]

    public init(model: Model, channels: [DebugChannel] = DebugChannel.allCases) {
        self.model = model
        self.channels = channels
    }

    public var hasAnimations: Bool { !model.animations.isEmpty }
    public var hasLights: Bool { !model.lights.isEmpty }
    public var hasCameras: Bool { !model.cameras.isEmpty }
    public var isMultiScene: Bool { model.scenes.count > 1 }
    public var hasSkin: Bool { !model.skins.isEmpty }
    public var hasMorphs: Bool { !model.morphs.isEmpty }
    public var availableDebugChannels: [ViewMode] { ViewMode.base + channels.map(ViewMode.channel) }
}
