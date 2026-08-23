import Foundation
import Observation

/// Dev-time `ClipPlaybackController` for `#Preview` — sample clips with local playhead.
@MainActor
@Observable
public final class MockPlaybackController: ClipPlaybackController {
    public private(set) var clips: [AnimationInfo]
    public private(set) var activeClip: AnimationInfo?
    public private(set) var isPlaying: Bool
    public private(set) var time: TimeInterval

    public var duration: TimeInterval { max(activeClip?.duration ?? 0, 0) }

    public init(
        clips: [AnimationInfo] = MockPlaybackController.sampleClips,
        activeClip: AnimationInfo? = nil,
        isPlaying: Bool = false,
        time: TimeInterval = 0
    ) {
        self.clips = clips
        self.activeClip = activeClip ?? clips.first
        self.isPlaying = isPlaying
        self.time = time
    }

    public func play() {
        guard !clips.isEmpty else { return }
        if activeClip == nil {
            activeClip = clips.first
        }
        isPlaying = true
    }

    public func pause() {
        isPlaying = false
    }

    public func seek(_ time: TimeInterval) {
        let span = max(duration, 0.001)
        self.time = duration > 0 ? min(max(time, 0), span) : 0
    }

    public func select(_ clip: AnimationInfo) {
        activeClip = clip
        time = 0
    }

    public func advance(by delta: TimeInterval) {
        guard isPlaying, duration > 0 else { return }
        time = (time + delta).truncatingRemainder(dividingBy: duration)
    }

    public static let sampleClips: [AnimationInfo] = [
        AnimationInfo(index: 0, name: "Idle", duration: 2),
        AnimationInfo(index: 1, name: "Walk", duration: 1.5),
    ]
}
