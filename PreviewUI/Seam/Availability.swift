import Foundation

/// Drives "show only what the model has" (DESIGN.md) for the view-mode menu: modes the file has
/// no data for are absent, not disabled.
public struct Availability: Sendable {
    /// Channels the file has data for; the base modes are prepended.
    public var channels: [DebugChannel]

    public init(channels: [DebugChannel] = DebugChannel.allCases) {
        self.channels = channels
    }

    /// View modes the file can render, in menu order.
    public var availableDebugChannels: [ViewMode] { ViewMode.base + channels.map(ViewMode.channel) }
}

extension Availability {
    /// Dev-time snapshot for `#Preview` and the catalog: a few common channels.
    public static let preview = Availability(channels: [.normals, .baseColor, .metallic])
}
