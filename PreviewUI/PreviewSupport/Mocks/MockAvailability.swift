import Foundation

/// Dev-time `Availability` for `#Preview` — configurable capability snapshot.
public struct MockAvailability: Availability, Sendable {
    public var hasAnimations: Bool
    public var hasLights: Bool
    public var availableDebugChannels: [ViewMode]

    public init(
        hasAnimations: Bool = false,
        hasLights: Bool = true,
        channels: [DebugChannel] = [.normals, .baseColor, .metallic]
    ) {
        self.hasAnimations = hasAnimations
        self.hasLights = hasLights
        self.availableDebugChannels = ViewMode.base + channels.map(ViewMode.channel)
    }
}
