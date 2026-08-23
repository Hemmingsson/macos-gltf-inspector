import Foundation

/// Dev-time `Availability` for `#Preview` — configurable capability snapshot.
public struct MockAvailability: Availability, Sendable {
    public var hasAnimations: Bool
    public var hasLights: Bool
    public var hasCameras: Bool
    public var isMultiScene: Bool
    public var hasSkin: Bool
    public var hasMorphs: Bool
    public var availableDebugChannels: [ViewMode]

    public init(
        hasAnimations: Bool = false,
        hasLights: Bool = true,
        hasCameras: Bool = false,
        isMultiScene: Bool = false,
        hasSkin: Bool = false,
        hasMorphs: Bool = false,
        channels: [DebugChannel] = [.normals, .baseColor, .metallic]
    ) {
        self.hasAnimations = hasAnimations
        self.hasLights = hasLights
        self.hasCameras = hasCameras
        self.isMultiScene = isMultiScene
        self.hasSkin = hasSkin
        self.hasMorphs = hasMorphs
        self.availableDebugChannels = ViewMode.base + channels.map(ViewMode.channel)
    }
}
