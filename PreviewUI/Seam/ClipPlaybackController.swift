import Foundation
import Observation

/// Live clip transport for the canvas playback bar. Mutable and per-window.
///
/// `SceneModel.animations` is the file inventory; this is the player. RealityKit's host
/// adapter wraps `PreviewClip`; WebKit uses `NoClipPlayback` until the page gains transport.
/// `PlaybackBar` ticks `advance(by:)`.
@MainActor
public protocol ClipPlaybackController: AnyObject, Observable {
    var clips: [AnimationInfo] { get }
    var activeClip: AnimationInfo? { get }
    var isPlaying: Bool { get }
    var time: TimeInterval { get }
    var duration: TimeInterval { get }

    func play()
    func pause()
    func seek(_ time: TimeInterval)
    func select(_ clip: AnimationInfo)
    /// Advance the playhead. `PlaybackBar` drives this while playing; a RealityKit adapter
    /// mirrors the clip player (RK owns time). WebKit's stub is a no-op.
    func advance(by delta: TimeInterval)
}
