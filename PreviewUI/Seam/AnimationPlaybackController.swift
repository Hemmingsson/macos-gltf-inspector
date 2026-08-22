import Foundation
import Observation

/// Live clip transport for the canvas playback bar. Mutable and per-window.
///
/// `SceneModel.animations` is the file inventory; this is the player. The host engine
/// adapter wraps RealityKit / `PreviewClip`. `PlaybackBar` ticks `advance(by:)`.
@MainActor
protocol AnimationPlaybackController: AnyObject, Observable {
    var clips: [AnimationInfo] { get }
    var activeClip: AnimationInfo? { get }
    var isPlaying: Bool { get }
    var time: TimeInterval { get }
    var duration: TimeInterval { get }

    func play()
    func pause()
    func seek(_ time: TimeInterval)
    func select(_ clip: AnimationInfo)
    /// Advance the playhead. `PlaybackBar` drives this while playing; the engine adapter
    /// mirrors the RealityKit player (RK owns time).
    func advance(by delta: TimeInterval)
}
