import Foundation

/// Wall clock for animation playback; tests inject a stepped clock instead of `ContinuousClock.now`.
@MainActor
public struct AnimationPlaybackClock: Sendable {
    public var now: @Sendable () -> ContinuousClock.Instant

    public init(now: @escaping @Sendable () -> ContinuousClock.Instant) {
        self.now = now
    }

    public static let live = AnimationPlaybackClock { ContinuousClock.now }
}
