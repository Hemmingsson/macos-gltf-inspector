import Foundation
import Observation
import PreviewUI
import RendererRealityKit

/// Live clip transport over `RealityClipPlayer`.
///
/// `advance(by:)` mirrors the RealityKit playhead (`PlaybackBar` ticks; RK owns time).
@MainActor
@Observable
final class EngineAnimationPlaybackController: ClipPlaybackController {
    private let player: RealityClipPlayer

    private(set) var clips: [AnimationInfo]
    private(set) var activeClip: AnimationInfo?
    private(set) var isPlaying = false
    private(set) var time: TimeInterval = 0

    var duration: TimeInterval { max(activeClip?.duration ?? 0, 0) }

    init(player: RealityClipPlayer) {
        self.player = player
        self.clips = player.clips.map {
            AnimationInfo(index: $0.id, name: $0.title, duration: $0.duration)
        }
        self.activeClip = self.clips.first
    }

    /// No model loaded yet: no clips.
    convenience init() {
        self.init(player: RealityClipPlayer())
    }

    /// Convenience from a loaded model (usable RealityKit clips + document name fallback).
    convenience init(loaded: EntityLoader.LoadedModel) {
        self.init(player: RealityClipPlayer(model: loaded))
    }

    func play() {
        guard !clips.isEmpty else { return }
        if !player.isStarted {
            startActiveClip(playing: true)
        } else {
            player.resume()
        }
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func seek(_ time: TimeInterval) {
        let span = max(duration, 0.001)
        let clamped = min(max(time, 0), span)
        self.time = duration > 0 ? clamped : 0
        player.time = self.time
    }

    func select(_ clip: AnimationInfo) {
        activeClip = clip
        time = 0
        startActiveClip(playing: isPlaying)
    }

    func advance(by _: TimeInterval) {
        guard isPlaying, player.isStarted, duration > 0 else { return }
        time = player.time.truncatingRemainder(dividingBy: duration)
    }

    private func startActiveClip(playing: Bool) {
        if player.start(clipID: activeClip?.id.index, playing: playing) {
            time = 0
        }
    }
}
