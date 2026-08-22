import Foundation
import Observation

/// Live clip transport for the canvas playback bar. Mutable and per-window.
///
/// `SceneModel.animations` is the file inventory; this is the player. The shell mock owns a
/// local clock; the engine adapter wraps `PreviewScene` / `PreviewClip`.
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
    /// Advance the playhead. The shell mock uses this as its clock; the engine adapter no-ops
    /// (RealityKit owns time) or mirrors the live player.
    func advance(by delta: TimeInterval)
}
