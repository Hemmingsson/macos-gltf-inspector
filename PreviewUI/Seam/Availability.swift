import Foundation

/// Drives "show only what the model has" (DESIGN.md). Every adaptive section and control
/// reads its visibility from here — never from a hard-coded `if` in a view.
public protocol Availability: Sendable {
    var hasAnimations: Bool { get }
    var hasLights: Bool { get }
    /// View modes the file can actually render, in menu order. Always starts with the
    /// base modes; channels the file lacks are absent, not disabled.
    var availableDebugChannels: [ViewMode] { get }
}
